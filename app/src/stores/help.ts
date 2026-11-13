import { defineStore } from "pinia";
import { computed, ref } from "vue";
import { getBackend } from "@/services/backend";
import {
  listHelpDismissals,
  saveHelpDismissal,
  type HelpHintKey,
} from "@/services/help-preferences";
import { useAuthStore } from "@/stores/auth";

export const useHelpStore = defineStore("help", () => {
  const loadedForUserId = ref<string | null>(null);
  const dismissedKeys = ref<string[]>([]);
  const loading = ref(false);
  const syncError = ref(false);
  let generation = 0;
  let activeUserId: string | null = null;
  const dismissed = computed(() => new Set(dismissedKeys.value));

  function reset() {
    generation++;
    loadedForUserId.value = null;
    activeUserId = null;
    dismissedKeys.value = [];
    loading.value = false;
    syncError.value = false;
  }

  async function loadForUser(userId: string): Promise<void> {
    if (
      loadedForUserId.value === userId ||
      (activeUserId === userId && loading.value)
    )
      return;
    if (activeUserId !== userId) reset();
    activeUserId = userId;
    const current = ++generation;
    const backend = getBackend();
    if (!backend) return;
    loading.value = true;
    try {
      const keys = await listHelpDismissals(backend.client, userId);
      if (current !== generation || useAuthStore().user?.id !== userId) return;
      dismissedKeys.value = [...new Set([...dismissedKeys.value, ...keys])];
      loadedForUserId.value = userId;
      syncError.value = false;
    } catch {
      if (current === generation) syncError.value = true;
    } finally {
      if (current === generation) loading.value = false;
    }
  }

  async function dismiss(key: HelpHintKey): Promise<{ synced: boolean }> {
    const userId = useAuthStore().user?.id;
    if (!userId || activeUserId !== userId) return { synced: false };
    if (!dismissedKeys.value.includes(key))
      dismissedKeys.value = [...dismissedKeys.value, key];
    const current = generation;
    const backend = getBackend();
    if (!backend) return { synced: false };
    try {
      await saveHelpDismissal(backend.client, userId, key);
      if (current === generation) syncError.value = false;
      return { synced: true };
    } catch {
      if (current === generation) syncError.value = true;
      return { synced: false };
    }
  }

  return {
    loadedForUserId,
    dismissedKeys,
    dismissed,
    loading,
    syncError,
    loadForUser,
    dismiss,
    reset,
  };
});
