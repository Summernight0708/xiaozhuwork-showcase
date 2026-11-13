import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  auth: {
    user: { id: "user-1", email: "user@example.edu" },
    profile: { display_name: "张同学" },
    logout: vi.fn(),
  },
  notifications: {
    unreadCount: 3,
    load: vi.fn(),
  },
  projects: {
    activeItems: [
      { project: { id: "project-1", name: "数据结构课程设计" } },
      { project: { id: "project-2", name: "数字逻辑实验" } },
    ],
    load: vi.fn(),
  },
  workspace: {
    project: { id: "project-1", name: "数据结构课程设计" },
    membership: { user_id: "user-1", role: "member", member_state: "active" },
    role: "member",
    loadBase: vi.fn(),
  },
  clearSessionScopedState: vi.fn(),
}));

vi.mock("@/stores/auth", () => ({ useAuthStore: () => mocks.auth }));
vi.mock("@/stores/notifications", () => ({
  useNotificationsStore: () => mocks.notifications,
}));
vi.mock("@/stores/projects", () => ({
  useProjectsStore: () => mocks.projects,
}));
vi.mock("@/stores/workspace", () => ({
  useWorkspaceStore: () => mocks.workspace,
}));
vi.mock("@/stores/session-state", () => ({
  clearSessionScopedState: mocks.clearSessionScopedState,
}));

import AppShell from "@/layouts/AppShell.vue";

const Dummy = defineComponent({
  template: '<div data-test="route-view">route</div>',
});

function makeRouter() {
  const projectRoutes = [
    ["project-overview", "/projects/:projectId"],
    ["project-todos", "/projects/:projectId/todos"],
    ["project-tasks", "/projects/:projectId/tasks"],
    ["task-create", "/projects/:projectId/tasks/new"],
    ["task-detail", "/projects/:projectId/tasks/:taskId"],
    ["project-files", "/projects/:projectId/files"],
    ["file-detail", "/projects/:projectId/files/:fileId"],
    ["project-reviews", "/projects/:projectId/reviews"],
    ["review-detail", "/projects/:projectId/reviews/:reviewRoundId"],
    ["project-members", "/projects/:projectId/members"],
    ["project-analytics", "/projects/:projectId/analytics"],
    ["project-permissions", "/projects/:projectId/permissions"],
    ["project-integrations", "/projects/:projectId/integrations"],
    ["project-invitations", "/projects/:projectId/invitations"],
    ["project-contributions", "/projects/:projectId/contributions"],
    ["contribution-detail", "/projects/:projectId/contributions/:reportId"],
    ["project-settings", "/projects/:projectId/settings"],
  ] as const;
  return createRouter({
    history: createMemoryHistory(),
    routes: [
      { name: "projects", path: "/projects", component: Dummy },
      { name: "projects-todos", path: "/projects/todos", component: Dummy },
      {
        name: "cross-project-overview",
        path: "/workspace/cross-project",
        component: Dummy,
      },
      { name: "notifications", path: "/notifications", component: Dummy },
      { name: "profile", path: "/profile", component: Dummy },
      { name: "settings", path: "/settings", component: Dummy },
      { name: "help-center", path: "/help", component: Dummy },
      { name: "help-article", path: "/help/:articleId", component: Dummy },
      { name: "login", path: "/login", component: Dummy },
      ...projectRoutes.map(([name, path]) => ({
        name,
        path,
        component: Dummy,
        meta: { project: true, keepAlive: true },
      })),
    ],
  });
}

async function mountShell(path = "/projects/project-1") {
  const router = makeRouter();
  await router.push(path);
  await router.isReady();
  const wrapper = mount(AppShell, {
    global: {
      plugins: [router],
      stubs: {
        TaskDetailDrawer: { template: '<div data-test="task-drawer" />' },
      },
    },
  });
  await flushPromises();
  return { wrapper, router };
}

describe("AppShell A3-S navigation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.notifications.unreadCount = 3;
    mocks.workspace.project.id = "project-1";
    mocks.workspace.role = "member";
    mocks.workspace.membership.role = "member";
    mocks.workspace.membership.member_state = "active";
  });

  it("keeps global navigation global and moves project routes into the sidebar", async () => {
    const { wrapper } = await mountShell();

    expect(wrapper.get(".brand").text()).toContain("小猪作业");
    expect(wrapper.get(".global-nav").text()).toContain("项目");
    expect(wrapper.get(".global-nav").text()).toContain("我的工作");
    expect(wrapper.get(".global-nav").text()).not.toContain("验收");

    const sidebar = wrapper.get(".project-sidebar");
    for (const label of [
      "概览",
      "工作",
      "任务",
      "文件",
      "验收",
      "成员",
      "邀请",
      "贡献与报告",
      "项目设置",
    ]) {
      expect(sidebar.text()).toContain(label);
    }
    expect(sidebar.text()).toContain("数据结构课程设计");
    expect(sidebar.text()).toContain("成员");
    expect(mocks.workspace.loadBase).toHaveBeenCalledWith("project-1");
  });

  it("hides leader-only tools from non-leader desktop and mobile navigation", async () => {
    for (const role of ["member", "admin", "observer"]) {
      mocks.workspace.role = role;
      mocks.workspace.membership.role = role;
      const { wrapper } = await mountShell();

      for (const menu of [
        wrapper.get(".sidebar-nav--secondary"),
        wrapper.get(".mobile-more-panel"),
      ]) {
        expect(menu.text()).not.toContain("高级权限");
        expect(menu.text()).not.toContain("日历订阅");
        expect(menu.text()).toContain("项目统计");
        expect(menu.text()).toContain("项目设置");
      }
      wrapper.unmount();
    }
  });

  it("shows both tools only for an active leader of the current project", async () => {
    mocks.workspace.role = "leader";
    mocks.workspace.membership.role = "leader";
    const { wrapper } = await mountShell();

    for (const menu of [
      wrapper.get(".sidebar-nav--secondary"),
      wrapper.get(".mobile-more-panel"),
    ]) {
      expect(menu.text()).toContain("高级权限");
      expect(menu.text()).toContain("日历订阅");
    }
    wrapper.unmount();

    mocks.workspace.membership.member_state = "pending";
    const { wrapper: inactive } = await mountShell();
    expect(inactive.get(".sidebar-nav--secondary").text()).not.toContain(
      "高级权限",
    );
    expect(inactive.get(".mobile-more-panel").text()).not.toContain("日历订阅");
    inactive.unmount();

    mocks.workspace.membership.member_state = "active";
    mocks.workspace.project.id = "project-2";
    const { wrapper: stale } = await mountShell();
    expect(stale.get(".sidebar-nav--secondary").text()).not.toContain(
      "高级权限",
    );
    expect(stale.get(".mobile-more-panel").text()).not.toContain("日历订阅");
    stale.unmount();
  });

  it("keeps notifications and logout inside the global account layer", async () => {
    const { wrapper } = await mountShell();

    expect(wrapper.get(".notification-badge").text()).toBe("3");
    expect(wrapper.get(".notification-badge").attributes("aria-hidden")).toBe(
      "true",
    );
    expect(wrapper.get(".notification-link").attributes("aria-label")).toBe(
      "通知，3 条未读",
    );
    const account = wrapper.get(".account-panel");
    expect(account.text()).toContain("个人资料");
    expect(account.text()).toContain("使用帮助");
    expect(account.text()).not.toContain("方案与升级");
    expect(wrapper.get(".global-nav").text()).toContain("方案与升级");
    expect(account.text()).not.toContain("全局设置");
    expect(account.text()).toContain("退出登录");

    await account.get("button").trigger("click");
    await flushPromises();
    expect(mocks.auth.logout).toHaveBeenCalledOnce();
  });

  it("closes account dropdown on outside click, Escape and route navigation", async () => {
    const { wrapper, router } = await mountShell();
    const menu = wrapper.get(".account-menu").element as HTMLDetailsElement;
    menu.open = true;
    document.body.dispatchEvent(
      new MouseEvent("pointerdown", { bubbles: true }),
    );
    expect(menu.open).toBe(false);

    menu.open = true;
    document.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Escape", bubbles: true }),
    );
    expect(menu.open).toBe(false);

    menu.open = true;
    await router.push("/notifications");
    await flushPromises();
    expect(menu.open).toBe(false);
    wrapper.unmount();
  });

  it("removes the unread indicator and accessible count when there are no unread messages", async () => {
    mocks.notifications.unreadCount = 0;
    const { wrapper } = await mountShell();

    expect(wrapper.find(".notification-badge").exists()).toBe(false);
    expect(wrapper.get(".notification-link").attributes("aria-label")).toBe(
      "通知",
    );
  });

  it("preserves mobile bottom navigation, KeepAlive and the shared task drawer", async () => {
    const { wrapper } = await mountShell();

    const mobile = wrapper.get(".mobile-project-nav");
    for (const label of ["概览", "工作", "任务", "文件", "更多"]) {
      expect(mobile.text()).toContain(label);
    }
    expect(mobile.text()).toContain("验收");
    expect(mobile.text()).toContain("成员");
    expect(mobile.text()).toContain("邀请");
    expect(mobile.text()).toContain("贡献与报告");
    expect(mobile.text()).toContain("项目设置");

    expect(wrapper.findComponent({ name: "KeepAlive" }).exists()).toBe(true);
    expect(wrapper.find('[data-test="task-drawer"]').exists()).toBe(true);
  });

  it("falls back inside the project for a direct mobile detail deep link", async () => {
    const { wrapper, router } = await mountShell(
      "/projects/project-1/files/file-2",
    );

    const back = wrapper.get(".mobile-context-bar button");
    expect(back.text()).toContain("返回文件");

    await back.trigger("click");
    await flushPromises();

    expect(router.currentRoute.value.name).toBe("project-files");
  });

  it("falls back to overview for a direct mobile secondary-page entry", async () => {
    const { wrapper, router } = await mountShell();

    await router.push("/projects/project-1/members");
    await flushPromises();
    const back = wrapper.get(".mobile-context-bar button");
    expect(back.text()).toContain("返回项目概览");

    await back.trigger("click");
    await flushPromises();

    expect(router.currentRoute.value.name).toBe("project-overview");
  });

  it("keeps detail routes highlighted under their owning project section", async () => {
    const { wrapper, router } = await mountShell(
      "/projects/project-1/tasks/task-7",
    );
    expect(
      wrapper
        .findAll(".sidebar-nav a.active")
        .some((link) => link.text() === "任务"),
    ).toBe(true);

    await router.push("/projects/project-1/files/file-2");
    await flushPromises();
    expect(
      wrapper
        .findAll(".sidebar-nav a.active")
        .some((link) => link.text() === "文件"),
    ).toBe(true);
  });
});
