import type { User } from "@supabase/supabase-js";
import { flushPromises, mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import { createMemoryHistory, createRouter } from "vue-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  listNotifications: vi.fn(),
  getUnreadNotificationCount: vi.fn(),
  markNotificationRead: vi.fn(),
  markAllNotificationsRead: vi.fn(),
  dismissNotification: vi.fn(),
  restoreNotification: vi.fn(),
  dismissReadNotifications: vi.fn(),
  resolveNotificationTarget: vi.fn(),
  listProjectSummaries: vi.fn(),
}));

vi.mock("@/services/backend", () => ({
  getBackend: () => ({ client: {} }),
}));
vi.mock("@/services/repository", () => ({
  createRepository: () => mocks,
}));

import NotificationsView from "@/views/NotificationsView.vue";
import { useAuthStore } from "@/stores/auth";

const row = {
  id: "notification-1",
  project_id: "project-1",
  recipient_id: "user-1",
  notification_type: "task_assignment",
  title: "新任务指派",
  entity_type: "task",
  entity_id: "task-1",
  message: "你收到了一项待确认的任务指派。",
  read_at: null,
  created_at: "2026-09-30T10:00:00Z",
  source_event_id: 1,
};

async function mountView() {
  const pinia = createPinia();
  setActivePinia(pinia);
  useAuthStore().$patch({ user: { id: "user-1" } as unknown as User });
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: "/notifications",
        name: "notifications",
        component: NotificationsView,
      },
      {
        path: "/projects/:projectId/todos",
        name: "project-todos",
        component: { template: "<div />" },
      },
      {
        path: "/projects/:projectId/tasks/:taskId",
        name: "task-detail",
        component: { template: "<div />" },
      },
      {
        path: "/projects/:projectId/reviews/:reviewRoundId",
        name: "review-detail",
        component: { template: "<div />" },
      },
      {
        path: "/projects/:projectId",
        name: "project-overview",
        component: { template: "<div />" },
      },
      {
        path: "/projects/:projectId/invitations",
        name: "project-invitations",
        component: { template: "<div />" },
      },
      {
        path: "/projects/:projectId/members",
        name: "project-members",
        component: { template: "<div />" },
      },
      {
        path: "/help",
        name: "help-center",
        component: { template: "<div />" },
      },
      {
        path: "/download",
        name: "download",
        component: { template: "<div />" },
      },
      {
        path: "/upgrade",
        name: "upgrade",
        component: { template: "<div />" },
      },
    ],
  });
  await router.push("/notifications");
  await router.isReady();

  const wrapper = mount(NotificationsView, {
    global: {
      plugins: [pinia, router],
      stubs: {
        VanButton: {
          emits: ["click"],
          template: "<button @click='$emit(\"click\")'><slot /></button>",
        },
        VanLoading: { template: "<div><slot /></div>" },
        VanEmpty: { template: "<div><slot /></div>" },
      },
    },
  });
  await flushPromises();
  return { wrapper, router };
}

describe("NotificationsView", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.listNotifications.mockResolvedValue([row]);
    mocks.getUnreadNotificationCount.mockResolvedValue(1);
    mocks.markNotificationRead.mockResolvedValue(true);
    mocks.markAllNotificationsRead.mockResolvedValue(1);
    mocks.dismissNotification.mockResolvedValue(true);
    mocks.restoreNotification.mockResolvedValue(true);
    mocks.dismissReadNotifications.mockResolvedValue(1);
    mocks.listProjectSummaries.mockResolvedValue([]);
    mocks.resolveNotificationTarget.mockResolvedValue({
      routeName: "task-detail",
      projectId: "project-1",
      entityId: "task-1",
    });
  });

  it("renders the authoritative feed facts and read action", async () => {
    const { wrapper } = await mountView();

    expect(wrapper.text()).toContain("新任务指派");
    expect(wrapper.text()).toContain("你收到了一项待确认的任务指派。");
    expect(wrapper.text()).toContain("未读");
    expect(wrapper.text()).toContain("全部标为已读");
  });

  it("fails closed instead of navigating when the server no longer resolves the target", async () => {
    mocks.resolveNotificationTarget.mockResolvedValueOnce(null);
    const { wrapper, router } = await mountView();

    const openButton = wrapper
      .findAll("button")
      .find((button) => button.text().includes("新任务指派"));
    expect(openButton).toBeDefined();
    await openButton!.trigger("click");
    await flushPromises();

    expect(router.currentRoute.value.name).toBe("notifications");
    expect(wrapper.text()).toContain("关联内容不存在，或你已没有访问权限。");
  });

  it("routes assignment events to the response workspace only after target authorization succeeds", async () => {
    const { wrapper, router } = await mountView();
    const openButton = wrapper
      .findAll("button")
      .find((button) => button.text().includes("新任务指派"));
    await openButton!.trigger("click");
    await flushPromises();

    expect(mocks.resolveNotificationTarget).toHaveBeenCalledWith(
      "notification-1",
    );
    expect(router.currentRoute.value.name).toBe("project-todos");
    expect(router.currentRoute.value.query.focus).toBe("response");
  });
  it("renders project-independent system announcements and opens their allow-listed global target", async () => {
    mocks.listNotifications.mockResolvedValueOnce([
      {
        ...row,
        id: "system-1",
        project_id: null,
        notification_type: "system_announcement",
        title: "小猪作业已更新",
        entity_type: "system_announcement",
        entity_id: "announcement-1",
        message: "查看本次更新内容。",
        source_event_id: null,
      },
    ]);
    mocks.resolveNotificationTarget.mockResolvedValueOnce({
      routeName: "help-center",
    });
    const { wrapper, router } = await mountView();

    expect(wrapper.text()).toContain("系统");
    const openButton = wrapper
      .findAll("button")
      .find((button) => button.text().includes("小猪作业已更新"));
    await openButton!.trigger("click");
    await flushPromises();

    expect(router.currentRoute.value.name).toBe("help-center");
  });
  it("dismisses a personal notification and presents an undo action", async () => {
    const { wrapper } = await mountView();
    await wrapper.get('button[aria-label="删除通知"]').trigger("click");
    await flushPromises();
    expect(mocks.dismissNotification).toHaveBeenCalledWith("notification-1");
    expect(wrapper.text()).toContain("撤销");
    const undo = wrapper
      .findAll("button")
      .find((button) => button.text() === "撤销");
    await undo!.trigger("click");
    await flushPromises();
    expect(mocks.restoreNotification).toHaveBeenCalledWith("notification-1");
  });
});
