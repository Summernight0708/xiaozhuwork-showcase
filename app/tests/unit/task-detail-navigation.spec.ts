/* eslint-disable vue/one-component-per-file -- local router test fixtures share this spec */
import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent } from "vue";
import {
  createMemoryHistory,
  createRouter,
  createWebHistory,
  type Router,
} from "vue-router";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/components/task/TaskDetailContent.vue", () => ({
  default: defineComponent({
    name: "TaskDetailContent",
    template: '<div data-test="task-detail-content" />',
  }),
}));

import TaskDetailPage from "@/views/TaskDetailPage.vue";

const Dummy = defineComponent({ template: "<div />" });

function makeRouter(history = createMemoryHistory()) {
  return createRouter({
    history,
    routes: [
      { path: "/notifications", name: "notifications", component: Dummy },
      {
        path: "/projects/:projectId/tasks",
        name: "project-tasks",
        component: Dummy,
      },
      {
        path: "/projects/:projectId/tasks/:taskId",
        name: "task-detail",
        component: TaskDetailPage,
      },
    ],
  });
}

async function mountTaskDetail(router: Router) {
  await router.isReady();
  const wrapper = mount(TaskDetailPage, {
    global: { plugins: [router] },
  });
  return wrapper;
}

describe("TaskDetailPage back navigation", () => {
  it("uses the project task list as a fallback for a direct deep link", async () => {
    const router = makeRouter();
    await router.push("/projects/project-1/tasks/task-1");
    const wrapper = await mountTaskDetail(router);

    await wrapper.get(".back-button").trigger("click");
    await flushPromises();

    expect(router.currentRoute.value.name).toBe("project-tasks");
    expect(router.currentRoute.value.params.projectId).toBe("project-1");
  });

  it("preserves safe web history instead of forcing the fallback", async () => {
    window.history.replaceState(null, "", "/");
    const router = makeRouter(createWebHistory());
    await router.push("/notifications");
    await router.push("/projects/project-1/tasks/task-1");
    const wrapper = await mountTaskDetail(router);
    const back = vi.spyOn(router, "back").mockImplementation(() => {});

    expect(router.options.history.state.back).toBe("/notifications");
    await wrapper.get(".back-button").trigger("click");

    expect(back).toHaveBeenCalledOnce();
  });
});
