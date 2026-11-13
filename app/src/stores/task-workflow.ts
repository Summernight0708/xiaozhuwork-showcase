import { defineStore } from "pinia";
import { ref } from "vue";

import { newRequestId } from "@/lib/command-adapter";
import { getBackend } from "@/services/backend";
import { runIdempotentCommand } from "@/services/command-runner";
import { domainErrorMessage, unknownErrorMessage } from "@/services/errors";
import {
  createTaskWorkflowRepository,
  type TaskHelpRequestRow,
  type UpstreamReworkRequestRow,
} from "@/services/task-workflow-repository";
import { useWorkspaceStore } from "@/stores/workspace";
import type { TaskRow } from "@/types/ui";

export const useTaskWorkflowStore = defineStore("task-workflow", () => {
  const projectId = ref<string | null>(null);
  const taskId = ref<string | null>(null);
  const helpRequests = ref<TaskHelpRequestRow[]>([]);
  const reworkRequests = ref<UpstreamReworkRequestRow[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const actionError = ref<string | null>(null);
  const pendingAction = ref<string | null>(null);
  let loadGeneration = 0;

  function reset() {
    loadGeneration += 1;
    projectId.value = null;
    taskId.value = null;
    helpRequests.value = [];
    reworkRequests.value = [];
    loading.value = false;
    error.value = null;
    actionError.value = null;
    pendingAction.value = null;
  }

  async function load(
    nextProjectId: string,
    nextTaskId: string,
    force = false,
  ) {
    const backend = getBackend();
    if (!backend) return;
    const sameContext =
      projectId.value === nextProjectId && taskId.value === nextTaskId;
    if (sameContext && loading.value && !force) return;
    if (
      sameContext &&
      helpRequests.value.length + reworkRequests.value.length > 0 &&
      !force
    ) {
      return;
    }

    const generation = ++loadGeneration;
    projectId.value = nextProjectId;
    taskId.value = nextTaskId;
    loading.value = true;
    error.value = null;
    if (!sameContext) {
      helpRequests.value = [];
      reworkRequests.value = [];
    }

    try {
      const repository = createTaskWorkflowRepository(backend.client);
      const [nextHelp, nextRework] = await Promise.all([
        repository.listTaskHelpRequests(nextProjectId, nextTaskId),
        repository.listRelatedUpstreamReworkRequests(nextProjectId, nextTaskId),
      ]);
      if (
        generation !== loadGeneration ||
        projectId.value !== nextProjectId ||
        taskId.value !== nextTaskId
      ) {
        return;
      }
      helpRequests.value = nextHelp;
      reworkRequests.value = nextRework;
    } catch (caught) {
      if (generation === loadGeneration)
        error.value = unknownErrorMessage(caught);
    } finally {
      if (generation === loadGeneration) loading.value = false;
    }
  }

  async function withAction<T>(key: string, action: () => Promise<T>) {
    if (pendingAction.value) throw new Error("已有操作正在进行");
    pendingAction.value = key;
    actionError.value = null;
    try {
      return await action();
    } catch (caught) {
      actionError.value = unknownErrorMessage(caught);
      throw caught;
    } finally {
      pendingAction.value = null;
    }
  }

  async function refreshContext(
    commandProjectId: string,
    commandTaskId: string,
  ) {
    const workspace = useWorkspaceStore();
    await Promise.all([
      workspace.refreshTasks(),
      load(commandProjectId, commandTaskId, true),
    ]);
  }

  async function createHelp(
    task: TaskRow,
    input: {
      message: string;
      targetUserId?: string;
      marksTaskBlocked: boolean;
    },
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("create-help", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => refreshContext(task.project_id, task.id),
        execute: (stableRequestId) =>
          backend.commands.createTaskHelpRequest({
            projectId: task.project_id,
            taskId: task.id,
            requestId: stableRequestId,
            expectedVersion: task.version,
            message: input.message,
            targetUserId: input.targetUserId,
            marksTaskBlocked: input.marksTaskBlocked,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshContext(task.project_id, task.id);
      return result;
    });
  }

  async function resolveHelp(help: TaskHelpRequestRow) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction(`resolve-help:${help.id}`, async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () =>
          refreshContext(help.project_id, help.task_id),
        execute: (stableRequestId) =>
          backend.commands.resolveTaskHelpRequest({
            projectId: help.project_id,
            helpRequestId: help.id,
            requestId: stableRequestId,
            expectedVersion: help.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshContext(help.project_id, help.task_id);
      return result;
    });
  }

  async function requestRework(
    downstream: TaskRow,
    upstream: TaskRow,
    requirement: string,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction(`request-rework:${upstream.id}`, async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () =>
          refreshContext(downstream.project_id, downstream.id),
        execute: (stableRequestId) =>
          backend.commands.requestUpstreamRework({
            projectId: downstream.project_id,
            downstreamTaskId: downstream.id,
            upstreamTaskId: upstream.id,
            requestId: stableRequestId,
            expectedDownstreamVersion: downstream.version,
            expectedUpstreamVersion: upstream.version,
            requirement,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshContext(downstream.project_id, downstream.id);
      return result;
    });
  }

  async function reviewRework(
    request: UpstreamReworkRequestRow,
    action: "approve" | "reject",
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const contextTaskId =
      taskId.value && projectId.value === request.project_id
        ? taskId.value
        : request.downstream_task_id;
    return withAction(`review-rework:${request.id}`, async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () =>
          refreshContext(request.project_id, contextTaskId),
        execute: (stableRequestId) =>
          backend.commands.reviewUpstreamRework({
            projectId: request.project_id,
            reworkRequestId: request.id,
            requestId: stableRequestId,
            expectedVersion: request.version,
            action,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshContext(request.project_id, contextTaskId);
      return result;
    });
  }

  return {
    projectId,
    taskId,
    helpRequests,
    reworkRequests,
    loading,
    error,
    actionError,
    pendingAction,
    reset,
    load,
    createHelp,
    resolveHelp,
    requestRework,
    reviewRework,
  };
});
