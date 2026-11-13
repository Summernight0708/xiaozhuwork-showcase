import { defineStore } from "pinia";
import { computed, ref } from "vue";

export interface TaskSourceState {
  routeName: string;
  projectId: string;
  taskId: string;
  scrollY: number;
  state: Record<string, string | number | boolean | null>;
}

export const useTaskNavigationStore = defineStore("task-navigation", () => {
  const source = ref<TaskSourceState | null>(null);
  const drawerProjectId = ref<string | null>(null);
  const drawerTaskId = ref<string | null>(null);

  const drawerOpen = computed(() => !!drawerTaskId.value);

  function rememberSource(next: TaskSourceState) {
    source.value = next;
  }

  function openDrawer(projectId: string, taskId: string) {
    drawerProjectId.value = projectId;
    drawerTaskId.value = taskId;
  }

  function closeDrawer() {
    drawerProjectId.value = null;
    drawerTaskId.value = null;
  }

  function consumeForFullPage() {
    if (!drawerTaskId.value || !drawerProjectId.value) return null;
    return {
      projectId: drawerProjectId.value,
      taskId: drawerTaskId.value,
      source: source.value,
    };
  }

  function clearSource() {
    source.value = null;
  }

  function reset() {
    source.value = null;
    closeDrawer();
  }

  return {
    source,
    drawerProjectId,
    drawerTaskId,
    drawerOpen,
    rememberSource,
    openDrawer,
    closeDrawer,
    consumeForFullPage,
    reset,
    clearSource,
  };
});
