import { createPinia, setActivePinia } from "pinia";
import { beforeEach, describe, expect, it } from "vitest";

import { clearSessionScopedState } from "@/stores/session-state";
import { useProjectsStore } from "@/stores/projects";
import { useTaskNavigationStore } from "@/stores/task-navigation";
import { useWorkspaceStore } from "@/stores/workspace";

describe("session scoped state", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it("clears cached project data and task navigation when the account changes", () => {
    const projects = useProjectsStore();
    const workspace = useWorkspaceStore();
    const navigation = useTaskNavigationStore();

    projects.$patch({
      items: [{ project: { id: "project-a" } }] as never,
      loaded: true,
    });
    workspace.$patch({
      projectId: "project-a",
      project: { id: "project-a" } as never,
      tasks: [{ id: "task-a", project_id: "project-a" }] as never,
    });
    navigation.rememberSource({
      routeName: "project-tasks",
      projectId: "project-a",
      taskId: "task-a",
      scrollY: 200,
      state: { search: "private" },
    });
    navigation.openDrawer("project-a", "task-a");

    clearSessionScopedState();

    expect(projects.items).toEqual([]);
    expect(projects.loaded).toBe(false);
    expect(workspace.projectId).toBeNull();
    expect(workspace.project).toBeNull();
    expect(workspace.tasks).toEqual([]);
    expect(navigation.drawerOpen).toBe(false);
    expect(navigation.source).toBeNull();
  });
});
