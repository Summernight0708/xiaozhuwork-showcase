import { computed, onActivated, watch } from "vue";
import { useRoute } from "vue-router";

import { useWorkspaceStore } from "@/stores/workspace";

export function useWorkspaceRoute() {
  const route = useRoute();
  const workspace = useWorkspaceStore();
  const projectId = computed(() => String(route.params.projectId || ""));

  async function load(force = false) {
    if (!projectId.value) return;
    await workspace.loadBase(projectId.value, force);
  }

  watch(projectId, () => void load(), { immediate: true });
  onActivated(() => void load());

  return { route, workspace, projectId, reload: () => load(true) };
}
