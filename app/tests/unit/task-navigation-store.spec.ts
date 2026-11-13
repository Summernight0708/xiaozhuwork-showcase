import { createPinia, setActivePinia } from "pinia";
import { beforeEach, describe, expect, it } from "vitest";

import { useTaskNavigationStore } from "@/stores/task-navigation";

describe("task navigation context", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it("keeps source filters, scroll and selected task when drawer expands to a full page", () => {
    const store = useTaskNavigationStore();
    store.rememberSource({
      routeName: "project-tasks",
      projectId: "project-1",
      taskId: "task-1",
      scrollY: 640,
      state: {
        search: "report",
        status: "blocked",
        sort: "deadline",
        page: 2,
      },
    });

    store.openDrawer("project-1", "task-1");

    expect(store.drawerTaskId).toBe("task-1");
    expect(store.source?.scrollY).toBe(640);
    expect(store.source?.state.search).toBe("report");

    const fullPageState = store.consumeForFullPage();
    expect(fullPageState?.taskId).toBe("task-1");
    expect(store.source?.state.page).toBe(2);
  });
});
