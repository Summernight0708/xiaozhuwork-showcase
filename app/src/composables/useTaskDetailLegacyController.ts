import { computed, onMounted, ref, watch } from "vue";
import { showToast } from "vant";

import { canActAsTaskParticipant } from "@/domain/task-actions";
import { canReviewTaskSubmission } from "@/domain/task-review";
import {
  isSubmissionFileType,
  normalizeRequiredSubmissionFileTypes,
  type SubmissionFileType,
} from "@/domain/submission-file-types";
import { useTaskWorkflowStore } from "@/stores/task-workflow";
import { useWorkspaceStore } from "@/stores/workspace";

export function useTaskDetailLegacyController(props: {
  projectId: string;
  taskId: string;
}) {
  const workspace = useWorkspaceStore();
  const workflow = useTaskWorkflowStore();

  const progressText = ref("");
  const blockedReason = ref("");
  const uploadInput = ref<HTMLInputElement | null>(null);
  const failedUploadFile = ref<File | null>(null);
  const submissionResetKey = ref(0);
  const submissionAutoSelectFileVersionId = ref<string | null>(null);
  const editTitle = ref("");
  const editDescription = ref("");
  const editDeadlineAt = ref("");
  const editWeight = ref(1);
  const editRequiredFileTypes = ref<SubmissionFileType[]>([]);
  const proposalDeadlineAt = ref("");
  const proposalWeight = ref(1);
  const proposalRequiredFileTypes = ref<SubmissionFileType[]>([]);
  const rejectionReason = ref("");
  const editDirty = ref(false);
  const dependencyDirty = ref(false);
  const selectedUpstreamTaskIds = ref<string[]>([]);

  const task = computed(() => workspace.findTask(props.taskId));
  const taskFiles = computed(() => workspace.taskFiles[props.taskId] ?? []);
  const versions = computed(() =>
    taskFiles.value.flatMap((file) => file.versions),
  );
  const requiredSubmissionFileTypes = computed<SubmissionFileType[]>(() => {
    const current = task.value;
    if (!current) return [];
    return normalizeRequiredSubmissionFileTypes(
      current.required_submission_file_types ??
        (isSubmissionFileType(current.required_submission_file_type)
          ? [current.required_submission_file_type]
          : []),
    );
  });
  const latestReview = computed(
    () =>
      workspace.reviews
        .filter((round) => round.task_id === props.taskId)
        .sort((a, b) => b.round_number - a.round_number)[0] ?? null,
  );
  const taskReviews = computed(() =>
    workspace.reviews
      .filter((round) => round.task_id === props.taskId)
      .sort((a, b) => b.round_number - a.round_number),
  );
  const taskReviewFiles = computed(() =>
    (workspace.reviewFiles ?? []).filter(
      (item) => item.task_id === props.taskId,
    ),
  );
  const isAssignee = computed(() =>
    canActAsTaskParticipant({
      role: workspace.role,
      currentUserId: workspace.currentUserId,
      targetUserId: task.value?.assignee_id,
    }),
  );
  const isParticipant = computed(
    () =>
      !!task.value &&
      (workspace.isTaskParticipant?.(task.value) ??
        task.value.assignee_id === workspace.currentUserId),
  );
  const canUploadTaskFile = computed(
    () =>
      !!task.value &&
      workspace.capabilities.canUploadFile &&
      ((workspace.isTaskParticipant?.(task.value) ??
        task.value.assignee_id === workspace.currentUserId) ||
        canEditTask.value),
  );
  const canRespond = computed(() => {
    const offer = task.value ? workspace.findOffer(task.value.id) : null;
    return canActAsTaskParticipant({
      role: workspace.role,
      currentUserId: workspace.currentUserId,
      targetUserId: offer?.target_user_id,
    });
  });
  const canReview = computed(
    () =>
      !!task.value &&
      !!latestReview.value &&
      canReviewTaskSubmission({
        role: workspace.role,
        currentUserId: workspace.currentUserId,
        task: task.value,
        round: latestReview.value,
      }),
  );
  const rejectedReason = computed(
    () => latestReview.value?.rejection_reason ?? "",
  );
  const upstreamTasks = computed(() => workspace.upstreamTasks(props.taskId));
  const downstreamTasks = computed(() =>
    workspace.downstreamTasks(props.taskId),
  );
  const dependencyState = computed(() =>
    workspace.dependencyState(props.taskId),
  );
  const taskChangeProposal = computed(() =>
    workspace.findTaskChangeProposal(props.taskId),
  );
  const pendingTaskChange = computed(() =>
    taskChangeProposal.value?.state === "pending"
      ? taskChangeProposal.value
      : null,
  );
  const dependencyCandidates = computed(() =>
    workspace.tasks.filter((candidate) => candidate.id !== props.taskId),
  );
  const canEditTask = computed(() => {
    if (!task.value || workspace.role === "observer") return false;
    if (
      ["awaiting_review", "completed", "canceled"].includes(task.value.status)
    ) {
      return false;
    }
    return (
      workspace.role === "leader" ||
      task.value.created_by === workspace.currentUserId
    );
  });
  const definitionLocked = computed(
    () => !!task.value?.accepted_at || task.value?.status !== "not_started",
  );
  const hasTaskActivity = computed(() => {
    const current = task.value;
    if (!current) return false;
    return (
      !!current.accepted_at ||
      !!current.first_submitted_at ||
      current.status !== "not_started" ||
      !!current.progress_text?.trim() ||
      (workspace.taskFiles[current.id]?.length ?? 0) > 0 ||
      taskReviews.value.length > 0
    );
  });
  const canProposeTaskChange = computed(
    () =>
      canEditTask.value &&
      hasTaskActivity.value &&
      task.value?.assignment_state === "assigned" &&
      !pendingTaskChange.value,
  );
  const canDecideTaskChange = computed(
    () =>
      !!pendingTaskChange.value &&
      pendingTaskChange.value.required_confirmer_id ===
        workspace.currentUserId &&
      task.value?.assignee_id === workspace.currentUserId,
  );

  function toDatetimeLocal(value: string) {
    const date = new Date(value);
    const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
    return local.toISOString().slice(0, 16);
  }

  function syncInputs() {
    progressText.value = task.value?.progress_text ?? "";
    blockedReason.value = task.value?.blocked_reason ?? "";
    if (task.value && !editDirty.value) {
      editTitle.value = task.value.title;
      editDescription.value = task.value.description ?? "";
      editDeadlineAt.value = toDatetimeLocal(task.value.deadline_at);
      editWeight.value = task.value.weight ?? 1;
      editRequiredFileTypes.value = [...requiredSubmissionFileTypes.value];
      if (!pendingTaskChange.value) {
        proposalDeadlineAt.value = toDatetimeLocal(task.value.deadline_at);
        proposalWeight.value = task.value.weight ?? 1;
        proposalRequiredFileTypes.value = [
          ...requiredSubmissionFileTypes.value,
        ];
      }
    }
    if (task.value && !dependencyDirty.value) {
      selectedUpstreamTaskIds.value = upstreamTasks.value.map(
        (upstream) => upstream.id,
      );
    }
  }

  async function refresh() {
    await workspace.loadBase(props.projectId, true);
    await Promise.all([
      workspace.loadTaskFiles(props.taskId, true),
      workspace.loadReviews(),
      workflow.load(props.projectId, props.taskId, true),
    ]);
    syncInputs();
  }

  async function handleResult(result: { ok: boolean }) {
    if (result.ok) showToast("操作成功");
    else showToast(workspace.actionError || "操作失败");
  }

  async function claim() {
    if (!task.value) return;
    await handleResult(await workspace.claimTask(task.value));
  }

  async function respond(action: "accept" | "reject") {
    if (!task.value) return;
    await handleResult(await workspace.respondToAssignment(task.value, action));
  }

  async function saveProgress(status: "in_progress" | "blocked") {
    if (!task.value) return;
    if (status === "blocked" && !blockedReason.value.trim()) {
      showToast("请填写阻塞原因");
      return;
    }
    await handleResult(
      await workspace.updateTaskProgress(
        task.value,
        status,
        progressText.value.trim() ||
          (status === "blocked" ? "任务当前阻塞" : "继续推进"),
        status === "blocked" ? blockedReason.value.trim() : undefined,
      ),
    );
  }

  async function saveTaskBasics() {
    if (!task.value) return;
    const deadline = new Date(editDeadlineAt.value);
    if (!editTitle.value.trim() || Number.isNaN(deadline.getTime())) {
      showToast("请填写有效的任务标题和截止时间");
      return;
    }
    const result = await workspace.editTask(task.value, {
      title: editTitle.value.trim(),
      description: editDescription.value.trim() || undefined,
      deadlineAt: deadline.toISOString(),
      weight:
        workspace.project?.contribution_mode === "weighted"
          ? editWeight.value
          : undefined,
      requiredSubmissionFileTypes: [...editRequiredFileTypes.value],
    });
    await handleResult(result);
    if (result.ok) editDirty.value = false;
    syncInputs();
  }

  async function proposeImportantChange() {
    if (!task.value) return;
    const deadline = new Date(proposalDeadlineAt.value);
    if (Number.isNaN(deadline.getTime())) {
      showToast("请填写有效的截止时间");
      return;
    }
    const result = await workspace.proposeTaskChange(task.value, {
      deadlineAt: deadline.toISOString(),
      weight:
        workspace.project?.contribution_mode === "weighted"
          ? proposalWeight.value
          : undefined,
      requiredSubmissionFileTypes: [...proposalRequiredFileTypes.value],
    });
    await handleResult(result);
    syncInputs();
  }

  async function decideImportantChange(action: "approve" | "reject") {
    if (!pendingTaskChange.value) return;
    const result = await workspace.respondToTaskChange(
      pendingTaskChange.value,
      action,
      action === "reject"
        ? rejectionReason.value.trim() || undefined
        : undefined,
    );
    await handleResult(result);
    if (result.ok) rejectionReason.value = "";
    syncInputs();
  }

  async function saveDependencies() {
    if (!task.value) return;
    const result = await workspace.setTaskDependencies(
      task.value,
      selectedUpstreamTaskIds.value,
    );
    await handleResult(result);
    if (result.ok) dependencyDirty.value = false;
    syncInputs();
  }

  function chooseUpload() {
    uploadInput.value?.click();
  }

  async function performUpload(file: File) {
    if (!task.value) return;
    const result = await workspace.uploadFile(task.value, file, "new_file");
    if (result.ok) {
      failedUploadFile.value = null;
      submissionAutoSelectFileVersionId.value = result.data.fileVersionId;
      if (uploadInput.value) uploadInput.value.value = "";
    } else {
      failedUploadFile.value = file;
    }
    await handleResult(result);
    syncInputs();
  }

  async function upload(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    await performUpload(file);
  }

  async function retryUpload() {
    if (!failedUploadFile.value) return;
    await performUpload(failedUploadFile.value);
  }

  async function submitReview(payload: {
    submissionText?: string;
    fileVersionIds: string[];
  }) {
    if (!task.value) return;
    const result = await workspace.submitReview(task.value, payload);
    await handleResult(result);
    if (result.ok) {
      submissionResetKey.value += 1;
      submissionAutoSelectFileVersionId.value = null;
    }
  }

  async function review(action: "approve" | "request_changes") {
    if (!task.value || !latestReview.value) return;
    if (action === "request_changes" && !blockedReason.value.trim()) {
      showToast("要求修改必须填写明确原因");
      return;
    }
    try {
      await handleResult(
        await workspace.reviewSubmission(
          task.value,
          latestReview.value,
          action,
          action === "request_changes" ? blockedReason.value.trim() : undefined,
        ),
      );
    } catch {
      showToast(workspace.actionError || "验收结果同步失败，请刷新核对");
    }
  }

  watch([task, versions], syncInputs, { immediate: true });
  onMounted(() => void refresh());

  return {
    workspace,
    task,
    taskFiles,
    versions,
    requiredSubmissionFileTypes,
    latestReview,
    taskReviews,
    taskReviewFiles,
    isAssignee,
    isParticipant,
    canUploadTaskFile,
    canRespond,
    canReview,
    rejectedReason,
    upstreamTasks,
    downstreamTasks,
    dependencyState,
    taskChangeProposal,
    pendingTaskChange,
    dependencyCandidates,
    canEditTask,
    definitionLocked,
    canProposeTaskChange,
    canDecideTaskChange,
    progressText,
    blockedReason,
    uploadInput,
    failedUploadFile,
    submissionResetKey,
    submissionAutoSelectFileVersionId,
    editTitle,
    editDescription,
    editDeadlineAt,
    editWeight,
    editRequiredFileTypes,
    proposalDeadlineAt,
    proposalWeight,
    proposalRequiredFileTypes,
    rejectionReason,
    editDirty,
    dependencyDirty,
    selectedUpstreamTaskIds,
    refresh,
    claim,
    respond,
    saveProgress,
    saveTaskBasics,
    proposeImportantChange,
    decideImportantChange,
    saveDependencies,
    chooseUpload,
    upload,
    retryUpload,
    performUpload,
    submitReview,
    review,
    workflow,
  };
}
