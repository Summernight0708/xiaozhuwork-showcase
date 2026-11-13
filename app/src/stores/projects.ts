import { defineStore } from "pinia";
import { computed, ref } from "vue";

import { newRequestId } from "@/lib/command-adapter";
import { getBackend } from "@/services/backend";
import { runIdempotentCommand } from "@/services/command-runner";
import { domainErrorMessage, unknownErrorMessage } from "@/services/errors";
import { createRepository } from "@/services/repository";
import type { ProjectSummary } from "@/types/ui";
import { useAuthStore } from "@/stores/auth";

export const useProjectsStore = defineStore("projects", () => {
  const items = ref<ProjectSummary[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const loaded = ref(false);
  const loadedUserId = ref<string | null>(null);
  let loadGeneration = 0;

  const activeItems = computed(() =>
    items.value.filter((item) => !item.project.archived_at),
  );

  async function load(force = false) {
    const backend = getBackend();
    const auth = useAuthStore();
    const userId = auth.user?.id ?? null;
    if (!backend || !userId) return;

    const sameUser = loadedUserId.value === userId;
    if (loaded.value && sameUser && !force) return;

    const generation = ++loadGeneration;
    if (!sameUser) {
      loadedUserId.value = userId;
      items.value = [];
      loaded.value = false;
    }
    loading.value = true;
    error.value = null;

    const isCurrentUser = () =>
      generation === loadGeneration && loadedUserId.value === userId;

    try {
      const nextItems = await createRepository(
        backend.client,
      ).listProjectSummaries(userId);
      if (!isCurrentUser()) return;
      items.value = nextItems;
      loaded.value = true;
    } catch (caught) {
      if (isCurrentUser()) error.value = unknownErrorMessage(caught);
    } finally {
      if (isCurrentUser()) loading.value = false;
    }
  }

  async function createProject(input: {
    name: string;
    courseName?: string;
    description?: string;
    startAt?: string;
    deadlineAt: string;
    timezone?: string;
    contributionMode?: "weighted" | "facts_only";
    allowMemberTaskCreation?: boolean;
    requireRealName?: boolean;
    requireStudentNumber?: boolean;
  }) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const requestId = newRequestId();
    const result = await runIdempotentCommand({
      requestId,
      maxTransportRetries: 1,
      execute: (stableRequestId) =>
        backend.commands.createProject({
          requestId: stableRequestId,
          expectedVersion: 0,
          name: input.name,
          courseName: input.courseName,
          description: input.description,
          startAt: input.startAt,
          deadlineAt: input.deadlineAt,
          timezone: input.timezone,
          contributionMode: input.contributionMode,
          allowMemberTaskCreation: input.allowMemberTaskCreation,
          requireRealName: input.requireRealName,
          requireStudentNumber: input.requireStudentNumber,
        }),
    });
    if (!result.ok) {
      error.value = domainErrorMessage(result.code);
      return result;
    }
    loaded.value = false;
    await load(true);
    return result;
  }

  function reset() {
    loadGeneration += 1;
    items.value = [];
    loading.value = false;
    error.value = null;
    loaded.value = false;
    loadedUserId.value = null;
  }

  function invalidate() {
    loaded.value = false;
  }

  return {
    items,
    activeItems,
    loading,
    error,
    loaded,
    load,
    createProject,
    reset,
    invalidate,
  };
});
