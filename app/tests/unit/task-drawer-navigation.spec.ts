import { createPinia, setActivePinia } from "pinia";
import { flushPromises, mount } from "@vue/test-utils";
import { createMemoryHistory, createRouter } from "vue-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

import TaskDetailDrawer from "@/components/task/TaskDetailDrawer.vue";
import { useTaskNavigationStore } from "@/stores/task-navigation";

describe("task drawer to full-page navigation", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    Object.defineProperty(window, "innerWidth", {
      configurable: true,
      value: 1024,
    });
    Object.defineProperty(window, "scrollTo", {
      configurable: true,
      value: vi.fn(),
    });
  });

  it("copies the stable full-page task URL while the drawer stays open", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: "/projects/:projectId/tasks",
          name: "project-tasks",
          component: { template: "<div />" },
        },
        {
          path: "/projects/:projectId/tasks/:taskId",
          name: "task-detail",
          component: { template: "<div />" },
        },
      ],
    });
    await router.push("/projects/project-1/tasks");
    await router.isReady();
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText },
    });

    const navigation = useTaskNavigationStore();
    navigation.openDrawer("project-1", "task-1");
    const wrapper = mount(TaskDetailDrawer, {
      global: {
        plugins: [router],
        stubs: {
          VanPopup: { template: "<div><slot /></div>" },
          TaskDetailContent: { template: "<div />" },
        },
      },
    });

    const copy = wrapper
      .findAll("button")
      .find((button) => button.text().includes("复制链接"));
    expect(copy).toBeDefined();
    await copy!.trigger("click");
    expect(writeText).toHaveBeenCalledWith(
      expect.stringContaining("/projects/project-1/tasks/task-1"),
    );
    expect(navigation.drawerOpen).toBe(true);
  });

  it("moves focus into the desktop drawer, closes on Escape, and restores the trigger", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: "/projects/:projectId/tasks",
          name: "project-tasks",
          component: { template: "<div>tasks</div>" },
        },
        {
          path: "/projects/:projectId/tasks/:taskId",
          name: "task-detail",
          component: { template: "<div>detail</div>" },
        },
      ],
    });
    await router.push("/projects/project-1/tasks");
    await router.isReady();

    const trigger = document.createElement("button");
    trigger.textContent = "open task";
    document.body.appendChild(trigger);
    trigger.focus();

    const navigation = useTaskNavigationStore();
    navigation.rememberSource({
      routeName: "project-tasks",
      projectId: "project-1",
      taskId: "task-1",
      scrollY: 0,
      state: {},
    });
    navigation.openDrawer("project-1", "task-1");

    const wrapper = mount(TaskDetailDrawer, {
      attachTo: document.body,
      global: {
        plugins: [router],
        stubs: {
          VanPopup: { template: "<div><slot /></div>" },
          TaskDetailContent: { template: "<div />" },
        },
      },
    });
    await flushPromises();

    expect(document.activeElement?.textContent?.trim()).toBe("关闭");
    await wrapper.find(".drawer-shell").trigger("keydown", { key: "Escape" });
    await flushPromises();

    expect(navigation.drawerOpen).toBe(false);
    expect(document.activeElement).toBe(trigger);

    wrapper.unmount();
    trigger.remove();
  });

  it("routes mobile task context directly to the full-page task URL", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: "/projects/:projectId/tasks",
          name: "project-tasks",
          component: { template: "<div>tasks</div>" },
        },
        {
          path: "/projects/:projectId/tasks/:taskId",
          name: "task-detail",
          component: { template: "<div>detail</div>" },
        },
      ],
    });
    await router.push("/projects/project-1/tasks");
    await router.isReady();
    Object.defineProperty(window, "innerWidth", {
      configurable: true,
      value: 390,
    });

    const navigation = useTaskNavigationStore();
    navigation.rememberSource({
      routeName: "project-tasks",
      projectId: "project-1",
      taskId: "task-1",
      scrollY: 320,
      state: { search: "mobile" },
    });
    navigation.openDrawer("project-1", "task-1");

    mount(TaskDetailDrawer, {
      global: {
        plugins: [router],
        stubs: {
          VanPopup: { template: "<div><slot /></div>" },
          TaskDetailContent: { template: "<div />" },
        },
      },
    });
    await flushPromises();

    expect(router.currentRoute.value.name).toBe("task-detail");
    expect(navigation.drawerOpen).toBe(false);
    expect(navigation.source?.state.search).toBe("mobile");
  });

  it("keeps list context while expanding to the stable task URL and returning", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: "/projects/:projectId/tasks",
          name: "project-tasks",
          component: { template: "<div>tasks</div>" },
        },
        {
          path: "/projects/:projectId/tasks/:taskId",
          name: "task-detail",
          component: { template: "<div>detail</div>" },
        },
      ],
    });
    await router.push("/projects/project-1/tasks");
    await router.isReady();

    const navigation = useTaskNavigationStore();
    navigation.rememberSource({
      routeName: "project-tasks",
      projectId: "project-1",
      taskId: "task-1",
      scrollY: 720,
      state: {
        search: "evidence",
        status: "blocked",
        sort: "deadline",
        page: 2,
      },
    });
    navigation.openDrawer("project-1", "task-1");

    const wrapper = mount(TaskDetailDrawer, {
      global: {
        plugins: [router],
        stubs: {
          VanPopup: { template: "<div><slot /></div>" },
          TaskDetailContent: { template: "<div data-test='task-content' />" },
        },
      },
    });

    const openFull = wrapper
      .findAll("button")
      .find((button) => button.text().includes("全页打开"));
    expect(openFull).toBeDefined();
    await openFull!.trigger("click");
    await flushPromises();

    expect(router.currentRoute.value.name).toBe("task-detail");
    expect(router.currentRoute.value.params).toMatchObject({
      projectId: "project-1",
      taskId: "task-1",
    });
    expect(navigation.source?.state).toMatchObject({
      search: "evidence",
      status: "blocked",
      page: 2,
    });
    expect(navigation.drawerOpen).toBe(false);

    router.back();
    await flushPromises();

    expect(router.currentRoute.value.name).toBe("project-tasks");
    expect(navigation.source?.scrollY).toBe(720);
    expect(navigation.source?.taskId).toBe("task-1");
  });
});
