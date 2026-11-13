import { defineStore } from "pinia";
import { computed, ref } from "vue";

import {
  capabilitiesForMembership,
  normalizeProjectRole,
  type ProjectRole,
} from "@/domain/access-control";
import type { ProjectEntitlement } from "@/domain/entitlements";
import {
  normalizeRequiredSubmissionFileTypes,
  submissionFileTypeLabel,
  type SubmissionFileType,
} from "@/domain/submission-file-types";
import {
  dependencyStateForTask,
  taskDisplayStatus as resolveTaskDisplayStatus,
} from "@/domain/task-display";
import {
  isAcceptedCollaborator as isAcceptedCollaboratorDomain,
  isTaskParticipant as isTaskParticipantDomain,
  taskResponsibilityKind as taskResponsibilityKindDomain,
} from "@/domain/task-participant";
import { newRequestId } from "@/lib/command-adapter";
import { getBackend } from "@/services/backend";
import { runIdempotentCommand } from "@/services/command-runner";
import {
  domainErrorMessage,
  leaveProjectErrorMessage,
  taskCreateErrorMessage,
  unknownErrorMessage,
} from "@/services/errors";
import { uploadTaskFile } from "@/services/file-upload";
import { createRepository } from "@/services/repository";
import type { ProjectStorageUsage } from "@/services/repository";
import { useAuthStore } from "@/stores/auth";
import type {
  AssignmentOfferRow,
  ContributionConfirmationRow,
  ContributionReportSnapshot,
  FileRow,
  FileUploadReservationRow,
  FileVersionRow,
  FinalFileDesignationRow,
  InvitationRow,
  JoinRequestRow,
  MembershipRow,
  ProjectRow,
  ReviewRoundRow,
  ReviewRoundFileRow,
  TaskDependencyRow,
  TaskChangeProposalRow,
  TaskCollaboratorRow,
  TaskPrimaryHandoffRow,
  TaskFile,
  TaskRow,
} from "@/types/ui";

export const useWorkspaceStore = defineStore("workspace", () => {
  const projectId = ref<string | null>(null);
  const project = ref<ProjectRow | null>(null);
  const membership = ref<MembershipRow | null>(null);
  const entitlement = ref<ProjectEntitlement | null>(null);
  const members = ref<MembershipRow[]>([]);
  const tasks = ref<TaskRow[]>([]);
  const taskDependencies = ref<TaskDependencyRow[]>([]);
  const assignmentOffers = ref<AssignmentOfferRow[]>([]);
  const taskCollaborators = ref<TaskCollaboratorRow[]>([]);
  const taskPrimaryHandoffs = ref<TaskPrimaryHandoffRow[]>([]);
  const taskChangeProposals = ref<TaskChangeProposalRow[]>([]);
  const files = ref<FileRow[]>([]);
  const fileVersions = ref<FileVersionRow[]>([]);
  const fileFinalDesignations = ref<FinalFileDesignationRow[]>([]);
  const fileReservations = ref<FileUploadReservationRow[]>([]);
  const storageUsage = ref<ProjectStorageUsage | null>(null);
  const taskFiles = ref<Record<string, TaskFile[]>>({});
  const reviews = ref<ReviewRoundRow[]>([]);
  const reviewFiles = ref<ReviewRoundFileRow[]>([]);
  const invitations = ref<InvitationRow[]>([]);
  const joinRequests = ref<JoinRequestRow[]>([]);
  const contributionReport = ref<ContributionReportSnapshot | null>(null);
  const contributionConfirmations = ref<ContributionConfirmationRow[]>([]);
  const loading = ref(false);
  const refreshing = ref(false);
  const error = ref<string | null>(null);
  const actionError = ref<string | null>(null);
  const pendingAction = ref<string | null>(null);
  const loadedUserId = ref<string | null>(null);
  let loadGeneration = 0;
  let taskRefreshGeneration = 0;

  const role = computed(() =>
    membership.value
      ? normalizeProjectRole({
          role: membership.value.role,
          isObserver: membership.value.is_observer,
        })
      : "member",
  );
  const capabilities = computed(() =>
    capabilitiesForMembership(
      membership.value
        ? {
            role: membership.value.role,
            isObserver: membership.value.is_observer,
          }
        : null,
      project.value?.allow_member_task_creation ?? true,
    ),
  );
  const currentUserId = computed(() => useAuthStore().user?.id ?? null);

  function memberName(userId: string | null | undefined) {
    if (!userId) return "未分配";
    const member = members.value.find((item) => item.user_id === userId);
    const nickname = member?.display_name_snapshot?.trim();
    if (nickname && nickname !== "成员") return nickname;
    if (userId === currentUserId.value) return "我";
    return member ? "昵称未设置或受隐私保护" : "成员资料不可见";
  }

  function clearProjectData() {
    project.value = null;
    membership.value = null;
    entitlement.value = null;
    members.value = [];
    tasks.value = [];
    taskDependencies.value = [];
    assignmentOffers.value = [];
    taskCollaborators.value = [];
    taskPrimaryHandoffs.value = [];
    taskChangeProposals.value = [];
    files.value = [];
    fileVersions.value = [];
    fileFinalDesignations.value = [];
    fileReservations.value = [];
    storageUsage.value = null;
    taskFiles.value = {};
    reviews.value = [];
    reviewFiles.value = [];
    invitations.value = [];
    joinRequests.value = [];
    contributionReport.value = null;
    contributionConfirmations.value = [];
    error.value = null;
    actionError.value = null;
  }

  function reset() {
    loadGeneration += 1;
    taskRefreshGeneration += 1;
    projectId.value = null;
    loadedUserId.value = null;
    loading.value = false;
    refreshing.value = false;
    pendingAction.value = null;
    clearProjectData();
  }

  async function loadBase(nextProjectId: string, force = false) {
    const backend = getBackend();
    const auth = useAuthStore();
    const userId = auth.user?.id ?? null;
    if (!backend || !userId) return;

    const sameContext =
      projectId.value === nextProjectId && loadedUserId.value === userId;
    if (sameContext && project.value && !force) return;
    if (sameContext && loading.value && !force) return;

    const generation = ++loadGeneration;
    if (!sameContext) {
      projectId.value = nextProjectId;
      loadedUserId.value = userId;
      clearProjectData();
    }
    loading.value = true;
    error.value = null;

    const isCurrentContext = () =>
      generation === loadGeneration &&
      projectId.value === nextProjectId &&
      loadedUserId.value === userId;

    try {
      const repository = createRepository(backend.client);
      const [
        nextProject,
        nextMembership,
        nextEntitlement,
        nextMembers,
        nextTasks,
        nextDependencies,
        nextOffers,
        nextCollaborators,
        nextPrimaryHandoffs,
        nextTaskChangeProposals,
      ] = await Promise.all([
        repository.getProject(nextProjectId),
        repository.getMembership(nextProjectId, userId),
        repository.getProjectEntitlement(nextProjectId),
        repository.listMembers(nextProjectId),
        repository.listTasks(nextProjectId),
        repository.listTaskDependencies(nextProjectId),
        repository.listAssignmentOffers(nextProjectId),
        repository.listTaskCollaborators(nextProjectId),
        repository.listTaskPrimaryHandoffs(nextProjectId),
        repository.listTaskChangeProposals(nextProjectId),
      ]);
      if (!isCurrentContext()) return;
      project.value = nextProject;
      membership.value = nextMembership;
      entitlement.value = nextEntitlement;
      members.value = nextMembers;
      tasks.value = nextTasks;
      taskDependencies.value = nextDependencies;
      assignmentOffers.value = nextOffers;
      taskCollaborators.value = nextCollaborators;
      taskPrimaryHandoffs.value = nextPrimaryHandoffs;
      taskChangeProposals.value = nextTaskChangeProposals;
    } catch (caught) {
      if (isCurrentContext()) error.value = unknownErrorMessage(caught);
    } finally {
      if (isCurrentContext()) loading.value = false;
    }
  }

  function activeProjectContext() {
    const activeProjectId = projectId.value;
    const userId = currentUserId.value;
    if (!activeProjectId || !userId || loadedUserId.value !== userId)
      return null;
    return { projectId: activeProjectId, userId };
  }

  function isProjectContextCurrent(context: {
    projectId: string;
    userId: string;
  }) {
    return (
      projectId.value === context.projectId &&
      loadedUserId.value === context.userId &&
      currentUserId.value === context.userId
    );
  }

  async function reloadBaseIfCurrent(targetProjectId: string) {
    const context = activeProjectContext();
    if (!context || context.projectId !== targetProjectId) return;
    await loadBase(targetProjectId, true);
  }

  async function refreshTasks() {
    const context = activeProjectContext();
    const backend = getBackend();
    if (!context || !backend) return;
    const generation = ++taskRefreshGeneration;
    refreshing.value = true;
    try {
      const repository = createRepository(backend.client);
      const [
        nextTasks,
        nextDependencies,
        nextOffers,
        nextCollaborators,
        nextPrimaryHandoffs,
        nextTaskChangeProposals,
      ] = await Promise.all([
        repository.listTasks(context.projectId),
        repository.listTaskDependencies(context.projectId),
        repository.listAssignmentOffers(context.projectId),
        repository.listTaskCollaborators(context.projectId),
        repository.listTaskPrimaryHandoffs(context.projectId),
        repository.listTaskChangeProposals(context.projectId),
      ]);
      if (!isProjectContextCurrent(context)) return;
      tasks.value = nextTasks;
      taskDependencies.value = nextDependencies;
      assignmentOffers.value = nextOffers;
      taskCollaborators.value = nextCollaborators;
      taskPrimaryHandoffs.value = nextPrimaryHandoffs;
      taskChangeProposals.value = nextTaskChangeProposals;
    } finally {
      if (generation === taskRefreshGeneration) refreshing.value = false;
    }
  }

  async function loadTaskFiles(taskId: string, force = false) {
    if (taskFiles.value[taskId] && !force) return taskFiles.value[taskId];
    const context = activeProjectContext();
    const backend = getBackend();
    if (!context || !backend) return [];
    const response = await createRepository(backend.client).getTaskFiles(
      taskId,
    );
    if (!isProjectContextCurrent(context)) return [];
    taskFiles.value[taskId] = response.files;
    return response.files;
  }

  async function loadStorageUsage() {
    const context = activeProjectContext();
    const backend = getBackend();
    if (!context || !backend) return;
    try {
      const usage = await createRepository(
        backend.client,
      ).getProjectStorageUsage(context.projectId);
      if (isProjectContextCurrent(context)) storageUsage.value = usage;
    } catch {
      // File browsing must continue if a quota query cannot be completed.
      if (isProjectContextCurrent(context)) storageUsage.value = null;
    }
  }

  async function loadFiles() {
    const context = activeProjectContext();
    const backend = getBackend();
    if (!context || !backend) return;
    const repository = createRepository(backend.client);
    const [result, reservations, designations] = await Promise.all([
      repository.listProjectFiles(context.projectId),
      repository.listFileReservations(context.projectId),
      repository.listFinalFileDesignations(context.projectId),
    ]);
    if (!isProjectContextCurrent(context)) return;
    files.value = result.files;
    fileVersions.value = result.versions;
    fileReservations.value = reservations;
    fileFinalDesignations.value = designations;
    await loadStorageUsage();
  }

  async function loadReviews() {
    const context = activeProjectContext();
    const backend = getBackend();
    if (!context || !backend) return;
    const repository = createRepository(backend.client);
    const [nextReviews, nextReviewFiles] = await Promise.all([
      repository.listReviews(context.projectId),
      repository.listReviewFiles(context.projectId),
    ]);
    if (!isProjectContextCurrent(context)) return;
    reviews.value = nextReviews;
    reviewFiles.value = nextReviewFiles;
  }

  async function loadInvitations() {
    const context = activeProjectContext();
    const backend = getBackend();
    if (!context || !backend) return;
    const repository = createRepository(backend.client);
    // Strict Day 4 deliberately does not grant browser SELECT on project_invitations:
    // raw invitation tokens are one-time command results and only join requests are readable.
    // Keep any invitation rows already held in memory instead of turning a successful
    // create command into a UI failure by querying a table the browser cannot read.
    const nextJoinRequests = await repository.listJoinRequests(
      context.projectId,
    );
    if (isProjectContextCurrent(context)) joinRequests.value = nextJoinRequests;
  }

  async function loadContributionReport() {
    const context = activeProjectContext();
    const backend = getBackend();
    if (!context || !backend) return;
    const repository = createRepository(backend.client);
    const nextReport = await repository.getContributionReport(
      context.projectId,
    );
    const nextConfirmations = nextReport
      ? await repository.listContributionConfirmations(nextReport.reportId)
      : [];
    if (!isProjectContextCurrent(context)) return;
    contributionReport.value = nextReport;
    contributionConfirmations.value = nextConfirmations;
  }

  function findTask(taskId: string) {
    return tasks.value.find((task) => task.id === taskId) ?? null;
  }

  function findTaskChangeProposal(taskId: string) {
    return (
      taskChangeProposals.value.find(
        (proposal) =>
          proposal.task_id === taskId && proposal.state === "pending",
      ) ??
      taskChangeProposals.value.find(
        (proposal) => proposal.task_id === taskId,
      ) ??
      null
    );
  }

  function dependencyState(taskId: string) {
    return dependencyStateForTask(taskId, tasks.value, taskDependencies.value);
  }

  function taskDisplayStatus(task: TaskRow) {
    return resolveTaskDisplayStatus(task, dependencyState(task.id).blocked);
  }

  function upstreamTasks(taskId: string) {
    const ids = new Set(
      taskDependencies.value
        .filter((dependency) => dependency.downstream_task_id === taskId)
        .map((dependency) => dependency.upstream_task_id),
    );
    return tasks.value.filter((task) => ids.has(task.id));
  }

  function downstreamTasks(taskId: string) {
    const ids = new Set(
      taskDependencies.value
        .filter((dependency) => dependency.upstream_task_id === taskId)
        .map((dependency) => dependency.downstream_task_id),
    );
    return tasks.value.filter((task) => ids.has(task.id));
  }

  function findOffer(taskId: string) {
    return (
      assignmentOffers.value.find(
        (offer) => offer.task_id === taskId && offer.state === "pending",
      ) ?? null
    );
  }

  function collaboratorsForTask(taskId: string) {
    return taskCollaborators.value.filter(
      (collaborator) => collaborator.task_id === taskId,
    );
  }

  function pendingPrimaryHandoff(taskId: string) {
    return (
      taskPrimaryHandoffs.value.find(
        (handoff) => handoff.task_id === taskId && handoff.state === "pending",
      ) ?? null
    );
  }

  function findCollaborator(taskId: string, userId = currentUserId.value) {
    if (!userId) return null;
    return (
      taskCollaborators.value
        .filter(
          (collaborator) =>
            collaborator.task_id === taskId &&
            collaborator.user_id === userId &&
            ["pending", "accepted"].includes(collaborator.state),
        )
        .sort(
          (a, b) => Date.parse(b.created_at) - Date.parse(a.created_at),
        )[0] ?? null
    );
  }

  function isAcceptedCollaborator(
    taskId: string,
    userId = currentUserId.value,
  ) {
    return isAcceptedCollaboratorDomain(
      taskCollaborators.value,
      taskId,
      userId,
    );
  }

  function isTaskParticipant(task: TaskRow, userId = currentUserId.value) {
    return isTaskParticipantDomain(task, taskCollaborators.value, userId);
  }

  function taskResponsibilityKind(task: TaskRow, userId = currentUserId.value) {
    return taskResponsibilityKindDomain(task, taskCollaborators.value, userId);
  }

  async function withAction<T>(key: string, action: () => Promise<T>) {
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

  async function createTask(input: {
    title: string;
    description?: string;
    deadlineAt: string;
    weight?: number;
    assignmentMode: "claimable" | "direct";
    assigneeId?: string;
    requiredSubmissionFileType?: SubmissionFileType | null;
    requiredSubmissionFileTypes?: SubmissionFileType[];
    requiresReview?: boolean;
  }) {
    if (!project.value) throw new Error("Project unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const commandProjectId = project.value.id;
    const commandProjectVersion = project.value.version;
    return withAction("create-task", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => reloadBaseIfCurrent(commandProjectId),
        execute: (stableRequestId) =>
          backend.commands.createTask({
            projectId: commandProjectId,
            requestId: stableRequestId,
            expectedVersion: commandProjectVersion,
            title: input.title,
            description: input.description,
            deadlineAt: input.deadlineAt,
            weight: input.weight,
            assignmentMode: input.assignmentMode,
            assigneeId: input.assigneeId,
            requiredSubmissionFileType: input.requiredSubmissionFileType,
            requiredSubmissionFileTypes: input.requiredSubmissionFileTypes,
            requiresReview: input.requiresReview,
          }),
      });
      if (!result.ok) actionError.value = taskCreateErrorMessage(result);
      else if (projectId.value === commandProjectId)
        await Promise.all([
          reloadBaseIfCurrent(commandProjectId),
          refreshTasks(),
        ]);
      return result;
    });
  }

  async function setTaskDependencies(task: TaskRow, upstreamTaskIds: string[]) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("task-dependencies", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.setTaskDependencies({
            projectId: task.project_id,
            downstreamTaskId: task.id,
            upstreamTaskIds,
            requestId: stableRequestId,
            expectedVersion: task.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function claimTask(task: TaskRow) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("claim-task", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.claimTask({
            projectId: task.project_id,
            taskId: task.id,
            requestId: stableRequestId,
            expectedVersion: task.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function respondToAssignment(
    task: TaskRow,
    action: "accept" | "reject",
  ) {
    const backend = getBackend();
    const offer = findOffer(task.id);
    if (!backend || !offer) throw new Error("Assignment unavailable");
    return withAction("assignment", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.respondToTaskAssignment({
            projectId: task.project_id,
            taskId: task.id,
            assignmentOfferId: offer.id,
            requestId: stableRequestId,
            expectedVersion: offer.version,
            action,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function inviteTaskCollaborator(task: TaskRow, userId: string) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const existing = findCollaborator(task.id, userId);
    return withAction("collaborator-invite", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.inviteTaskCollaborator({
            projectId: task.project_id,
            taskId: task.id,
            userId,
            requestId: stableRequestId,
            expectedVersion: existing?.version ?? 0,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function respondToTaskCollaborator(
    collaborator: TaskCollaboratorRow,
    action: "accept" | "reject",
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("collaborator-response", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.respondToTaskCollaborator({
            projectId: collaborator.project_id,
            taskId: collaborator.task_id,
            collaboratorId: collaborator.id,
            action,
            requestId: stableRequestId,
            expectedVersion: collaborator.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function removeTaskCollaborator(collaborator: TaskCollaboratorRow) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("collaborator-remove", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.removeTaskCollaborator({
            projectId: collaborator.project_id,
            taskId: collaborator.task_id,
            collaboratorId: collaborator.id,
            requestId: stableRequestId,
            expectedVersion: collaborator.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function leaveTaskCollaboration(collaborator: TaskCollaboratorRow) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("collaborator-leave", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.leaveTaskCollaboration({
            projectId: collaborator.project_id,
            taskId: collaborator.task_id,
            collaboratorId: collaborator.id,
            requestId: stableRequestId,
            expectedVersion: collaborator.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function requestTaskPrimaryHandoff(
    task: TaskRow,
    targetUserId: string,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("primary-handoff-request", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.requestTaskPrimaryHandoff({
            projectId: task.project_id,
            taskId: task.id,
            targetUserId,
            requestId: stableRequestId,
            expectedTaskVersion: task.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function respondTaskPrimaryHandoff(
    task: TaskRow,
    handoff: TaskPrimaryHandoffRow,
    action: "accept" | "reject",
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("primary-handoff-response", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.respondTaskPrimaryHandoff({
            projectId: task.project_id,
            taskId: task.id,
            handoffId: handoff.id,
            action,
            requestId: stableRequestId,
            expectedHandoffVersion: handoff.version,
            expectedTaskVersion: task.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function cancelTaskPrimaryHandoff(
    task: TaskRow,
    handoff: TaskPrimaryHandoffRow,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("primary-handoff-cancel", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.cancelTaskPrimaryHandoff({
            projectId: task.project_id,
            taskId: task.id,
            handoffId: handoff.id,
            requestId: stableRequestId,
            expectedHandoffVersion: handoff.version,
            expectedTaskVersion: task.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function unassignTaskPrimary(task: TaskRow) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("primary-unassign", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.unassignTaskPrimary({
            projectId: task.project_id,
            taskId: task.id,
            requestId: stableRequestId,
            expectedTaskVersion: task.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function updateTaskProgress(
    task: TaskRow,
    status: "in_progress" | "blocked",
    progressText: string,
    blockedReason?: string,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("task-progress", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.updateTaskProgress({
            projectId: task.project_id,
            taskId: task.id,
            requestId: stableRequestId,
            expectedVersion: task.version,
            status,
            progressText,
            blockedReason,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function uploadFile(
    task: TaskRow,
    file: File,
    mode: "new_file" | "new_version",
    targetFileId?: string,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("file-upload", async () => {
      const targetFile =
        mode === "new_version" && targetFileId
          ? files.value.find((item) => item.id === targetFileId)
          : null;
      if (mode === "new_version" && !targetFile) {
        throw new Error("Target file unavailable");
      }
      const result = await uploadTaskFile({
        projectId: task.project_id,
        taskId: task.id,
        expectedVersion: targetFile?.version ?? task.version,
        file,
        mode,
        targetFileId,
        reserve: backend.commands.reserveTaskFileUpload,
        storageUpload: (objectPath, upload, options) =>
          backend.client.storage
            .from("teamup-files")
            .upload(objectPath, upload, options),
        finalize: (body) =>
          backend.client.functions.invoke("finalize-task-file-upload", {
            body,
          }),
        requestIdFactory: newRequestId,
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await Promise.all([
        refreshTasks(),
        loadTaskFiles(task.id, true),
        loadFiles(),
      ]);
      return result;
    });
  }

  async function markTaskFileReference(
    task: TaskRow,
    fileId: string,
    expectedVersion: number,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("file-reference", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => {
          await loadTaskFiles(task.id, true);
        },
        execute: (stableRequestId) =>
          backend.commands.markTaskFileReference({
            projectId: task.project_id,
            taskId: task.id,
            fileId,
            requestId: stableRequestId,
            expectedVersion,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await Promise.all([loadTaskFiles(task.id, true), loadFiles()]);
      return result;
    });
  }

  async function submitReview(
    task: TaskRow,
    input: { submissionText?: string; fileVersionIds: string[] },
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("submit-review", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.submitTaskForReview({
            projectId: task.project_id,
            taskId: task.id,
            submissionText: input.submissionText,
            fileVersionIds: input.fileVersionIds,
            requestId: stableRequestId,
            expectedVersion: task.version,
          }),
      });
      if (!result.ok) {
        const requiredTypes = normalizeRequiredSubmissionFileTypes(
          Array.isArray(result.details?.requiredFileTypes)
            ? result.details.requiredFileTypes
            : typeof result.details?.requiredFileType === "string"
              ? [result.details.requiredFileType]
              : [],
        );
        actionError.value =
          result.details?.reason === "required_file_type_missing" &&
          requiredTypes.length > 0
            ? `此任务要求提交内容中至少包含以下任一类型：${requiredTypes.map(submissionFileTypeLabel).join("、")}。`
            : domainErrorMessage(result.code);
      }
      await Promise.all([refreshTasks(), loadReviews()]);
      return result;
    });
  }

  async function reviewSubmission(
    task: TaskRow,
    round: ReviewRoundRow,
    action: "approve" | "request_changes",
    rejectionReason?: string,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("review", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: loadReviews,
        execute: (stableRequestId) =>
          backend.commands.reviewTaskSubmission({
            projectId: task.project_id,
            taskId: task.id,
            reviewRoundId: round.id,
            action,
            rejectionReason,
            requestId: stableRequestId,
            expectedVersion: round.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await Promise.all([refreshTasks(), loadReviews()]);
      if (result.ok && projectId.value === task.project_id) {
        const expectedTaskStatus =
          action === "approve" ? "completed" : "in_progress";
        const expectedReviewState =
          action === "approve" ? "approved" : "rejected";
        const persisted = () =>
          tasks.value.find((item) => item.id === task.id)?.status ===
            expectedTaskStatus &&
          reviews.value.find((item) => item.id === round.id)?.state ===
            expectedReviewState;
        // Never announce a completed task based solely on a processed-round
        // response: independently verify persisted task AND round facts.
        if (!persisted()) {
          await Promise.all([refreshTasks(), loadReviews()]);
          if (!persisted()) {
            throw new Error(
              "验收结果与服务端任务状态不一致，请刷新后联系管理员核查",
            );
          }
        }
      }
      return result;
    });
  }

  async function correctReviewRequestChanges(
    task: TaskRow,
    round: ReviewRoundRow,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("review-correction", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => {
          await Promise.all([refreshTasks(), loadReviews()]);
        },
        execute: (stableRequestId) =>
          backend.commands.correctTaskReviewRequestChanges({
            projectId: task.project_id,
            taskId: task.id,
            reviewRoundId: round.id,
            requestId: stableRequestId,
            expectedTaskVersion: task.version,
            expectedReviewVersion: round.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await Promise.all([refreshTasks(), loadReviews()]);
      return result;
    });
  }

  async function updateMemberRole(
    member: MembershipRow,
    targetRole: Exclude<ProjectRole, "leader">,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("member-role", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => reloadBaseIfCurrent(member.project_id),
        execute: (stableRequestId) =>
          backend.commands.updateProjectMemberRole({
            projectId: member.project_id,
            membershipId: member.id,
            targetRole,
            requestId: stableRequestId,
            expectedVersion: member.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await reloadBaseIfCurrent(member.project_id);
      return result;
    });
  }

  async function removeMember(member: MembershipRow) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("remove-member", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => reloadBaseIfCurrent(member.project_id),
        execute: (stableRequestId) =>
          backend.commands.removeProjectMember({
            projectId: member.project_id,
            membershipId: member.id,
            requestId: stableRequestId,
            expectedVersion: member.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await reloadBaseIfCurrent(member.project_id);
      return result;
    });
  }

  async function leaveProject() {
    if (!project.value || !membership.value)
      throw new Error("Project unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const activeProjectId = project.value.id;
    const membershipVersion = membership.value.version;
    return withAction("leave-project", async () => {
      const result = await runIdempotentCommand({
        requestId: newRequestId(),
        maxTransportRetries: 1,
        onStaleVersion: async () => reloadBaseIfCurrent(activeProjectId),
        execute: (stableRequestId) =>
          backend.commands.leaveProject({
            projectId: activeProjectId,
            requestId: stableRequestId,
            expectedVersion: membershipVersion,
          }),
      });
      if (!result.ok) actionError.value = leaveProjectErrorMessage(result);
      if (result.ok && projectId.value === activeProjectId) {
        clearProjectData();
        projectId.value = null;
      } else if (!result.ok) {
        await reloadBaseIfCurrent(activeProjectId);
      }
      return result;
    });
  }

  async function transferLeadership(member: MembershipRow) {
    if (!project.value) throw new Error("Project unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const projectVersion = project.value.version;
    return withAction("transfer-leadership", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => reloadBaseIfCurrent(member.project_id),
        execute: (stableRequestId) =>
          backend.commands.transferProjectLeadership({
            projectId: member.project_id,
            targetMembershipId: member.id,
            requestId: stableRequestId,
            expectedVersion: projectVersion,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await reloadBaseIfCurrent(member.project_id);
      return result;
    });
  }

  async function editTask(
    task: TaskRow,
    input: {
      title: string;
      description?: string;
      deadlineAt: string;
      weight?: number;
      requiredSubmissionFileType?: SubmissionFileType | null;
      requiredSubmissionFileTypes?: SubmissionFileType[];
    },
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("edit-task", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.editTask({
            projectId: task.project_id,
            taskId: task.id,
            requestId: stableRequestId,
            expectedVersion: task.version,
            title: input.title,
            description: input.description,
            deadlineAt: input.deadlineAt,
            weight: input.weight,
            requiredSubmissionFileType: input.requiredSubmissionFileType,
            requiredSubmissionFileTypes: input.requiredSubmissionFileTypes,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function proposeTaskChange(
    task: TaskRow,
    input: {
      deadlineAt: string;
      weight?: number;
      requiredSubmissionFileType?: SubmissionFileType | null;
      requiredSubmissionFileTypes?: SubmissionFileType[];
    },
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("task-change-proposal", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.proposeTaskChange({
            projectId: task.project_id,
            taskId: task.id,
            deadlineAt: input.deadlineAt,
            weight: input.weight,
            requestId: stableRequestId,
            expectedTaskVersion: task.version,
            requiredSubmissionFileType: input.requiredSubmissionFileType,
            requiredSubmissionFileTypes: input.requiredSubmissionFileTypes,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function respondToTaskChange(
    proposal: TaskChangeProposalRow,
    action: "approve" | "reject",
    rejectionReason?: string,
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("task-change-decision", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: refreshTasks,
        execute: (stableRequestId) =>
          backend.commands.respondToTaskChange({
            projectId: proposal.project_id,
            taskId: proposal.task_id,
            proposalId: proposal.id,
            action,
            rejectionReason,
            requestId: stableRequestId,
            expectedProposalVersion: proposal.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await refreshTasks();
      return result;
    });
  }

  async function setTaskFileVersionFinal(
    fileVersionId: string,
    isFinal: boolean,
  ) {
    if (!project.value) throw new Error("Project unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const activeProjectId = project.value.id;
    const designation = fileFinalDesignations.value.find(
      (item) => item.file_version_id === fileVersionId,
    );
    const designationVersion = designation?.version ?? 0;
    return withAction("final-file", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => {
          if (projectId.value === activeProjectId) await loadFiles();
        },
        execute: (stableRequestId) =>
          backend.commands.setTaskFileVersionFinal({
            projectId: activeProjectId,
            fileVersionId,
            requestId: stableRequestId,
            expectedVersion: designationVersion,
            isFinal,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      if (projectId.value === activeProjectId) await loadFiles();
      return result;
    });
  }

  async function updateProjectSettings(input: {
    name: string;
    courseName?: string;
    description?: string;
    startAt?: string;
    deadlineAt: string;
    timezone: string;
    contributionMode: "weighted" | "facts_only";
    allowMemberTaskCreation?: boolean;
    autoPenaltyEnabled: boolean;
    requireRealName: boolean;
    requireStudentNumber: boolean;
  }) {
    if (!project.value) throw new Error("Project unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const commandProjectId = project.value.id;
    const commandProjectVersion = project.value.version;
    return withAction("project-settings", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => reloadBaseIfCurrent(commandProjectId),
        execute: (stableRequestId) =>
          backend.commands.updateProjectSettings({
            projectId: commandProjectId,
            requestId: stableRequestId,
            expectedVersion: commandProjectVersion,
            ...input,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      await reloadBaseIfCurrent(commandProjectId);
      return result;
    });
  }

  async function createInvite(
    mode: "direct" | "approval",
    expiresInDays?: number,
    maxUses?: number,
  ) {
    if (!project.value) throw new Error("Project unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const commandProjectId = project.value.id;
    const commandProjectVersion = project.value.version;
    return withAction("invite", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => reloadBaseIfCurrent(commandProjectId),
        execute: (stableRequestId) =>
          backend.commands.createProjectInvite({
            projectId: commandProjectId,
            requestId: stableRequestId,
            expectedVersion: commandProjectVersion,
            mode,
            expiresInDays,
            maxUses,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      if (projectId.value === commandProjectId)
        await Promise.all([
          reloadBaseIfCurrent(commandProjectId),
          loadInvitations(),
        ]);
      return result;
    });
  }

  async function renewInvite(
    invite: Pick<InvitationRow, "id" | "version">,
    extendDays = 7,
  ) {
    if (!project.value) throw new Error("Project unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const activeProjectId = project.value.id;
    return withAction("renew-invite", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => {
          if (projectId.value === activeProjectId) await loadInvitations();
        },
        execute: (stableRequestId) =>
          backend.commands.renewProjectInvite({
            projectId: activeProjectId,
            invitationId: invite.id,
            requestId: stableRequestId,
            expectedVersion: invite.version,
            extendDays,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      if (projectId.value === activeProjectId) await loadInvitations();
      return result;
    });
  }

  async function revokeInvite(invite: Pick<InvitationRow, "id" | "version">) {
    if (!project.value) throw new Error("Project unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const activeProjectId = project.value.id;
    return withAction("revoke-invite", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => {
          if (projectId.value === activeProjectId) await loadInvitations();
        },
        execute: (stableRequestId) =>
          backend.commands.revokeProjectInvite({
            projectId: activeProjectId,
            invitationId: invite.id,
            requestId: stableRequestId,
            expectedVersion: invite.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      if (projectId.value === activeProjectId) await loadInvitations();
      return result;
    });
  }

  async function reviewJoinRequest(
    request: JoinRequestRow,
    action: "approve" | "reject",
  ) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return withAction("join-request", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => {
          if (projectId.value === request.project_id) await loadInvitations();
        },
        execute: (stableRequestId) =>
          backend.commands.reviewProjectJoinRequest({
            projectId: request.project_id,
            joinRequestId: request.id,
            action,
            requestId: stableRequestId,
            expectedVersion: request.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      if (projectId.value === request.project_id)
        await Promise.all([
          loadInvitations(),
          reloadBaseIfCurrent(request.project_id),
        ]);
      return result;
    });
  }

  async function createContributionReport() {
    if (!project.value) throw new Error("Project unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    const commandProjectId = project.value.id;
    const commandProjectVersion = project.value.version;
    return withAction("create-report", async () => {
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => reloadBaseIfCurrent(commandProjectId),
        execute: (stableRequestId) =>
          backend.commands.createContributionReport({
            projectId: commandProjectId,
            requestId: stableRequestId,
            expectedVersion: commandProjectVersion,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      if (projectId.value === commandProjectId)
        await Promise.all([
          reloadBaseIfCurrent(commandProjectId),
          loadContributionReport(),
        ]);
      return result;
    });
  }

  async function confirmContributionReport() {
    const backend = getBackend();
    if (!backend || !contributionReport.value)
      throw new Error("Report unavailable");
    return withAction("confirm-report", async () => {
      const report = contributionReport.value!;
      const requestId = newRequestId();
      const result = await runIdempotentCommand({
        requestId,
        maxTransportRetries: 1,
        onStaleVersion: async () => {
          if (projectId.value === report.projectId)
            await loadContributionReport();
        },
        execute: (stableRequestId) =>
          backend.commands.confirmContributionReport({
            projectId: report.projectId,
            reportId: report.reportId,
            requestId: stableRequestId,
            expectedVersion: report.version,
          }),
      });
      if (!result.ok) actionError.value = domainErrorMessage(result.code);
      if (projectId.value === report.projectId) await loadContributionReport();
      return result;
    });
  }

  async function exportReport(format: "csv" | "pdf") {
    if (!contributionReport.value) throw new Error("Report unavailable");
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");
    return createRepository(backend.client).exportContributionReport(
      contributionReport.value.reportId,
      format,
    );
  }

  return {
    projectId,
    project,
    membership,
    entitlement,
    members,
    tasks,
    taskDependencies,
    assignmentOffers,
    taskCollaborators,
    taskPrimaryHandoffs,
    taskChangeProposals,
    files,
    fileVersions,
    fileFinalDesignations,
    fileReservations,
    taskFiles,
    storageUsage,
    reviews,
    reviewFiles,
    invitations,
    joinRequests,
    contributionReport,
    contributionConfirmations,
    loading,
    refreshing,
    error,
    actionError,
    pendingAction,
    role,
    capabilities,
    currentUserId,
    memberName,
    reset,
    loadBase,
    refreshTasks,
    loadTaskFiles,
    loadFiles,
    loadReviews,
    loadStorageUsage,
    loadInvitations,
    loadContributionReport,
    findTask,
    findTaskChangeProposal,
    dependencyState,
    taskDisplayStatus,
    upstreamTasks,
    downstreamTasks,
    findOffer,
    collaboratorsForTask,
    pendingPrimaryHandoff,
    findCollaborator,
    isAcceptedCollaborator,
    isTaskParticipant,
    taskResponsibilityKind,
    createTask,
    setTaskDependencies,
    claimTask,
    respondToAssignment,
    inviteTaskCollaborator,
    respondToTaskCollaborator,
    removeTaskCollaborator,
    leaveTaskCollaboration,
    requestTaskPrimaryHandoff,
    respondTaskPrimaryHandoff,
    cancelTaskPrimaryHandoff,
    unassignTaskPrimary,
    updateTaskProgress,
    uploadFile,
    markTaskFileReference,
    submitReview,
    reviewSubmission,
    correctReviewRequestChanges,
    updateMemberRole,
    removeMember,
    leaveProject,
    transferLeadership,
    editTask,
    proposeTaskChange,
    respondToTaskChange,
    setTaskFileVersionFinal,
    updateProjectSettings,
    createInvite,
    renewInvite,
    revokeInvite,
    reviewJoinRequest,
    createContributionReport,
    confirmContributionReport,
    exportReport,
  };
});
