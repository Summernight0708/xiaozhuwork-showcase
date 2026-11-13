<script setup lang="ts">
import { computed, getCurrentInstance, ref, watch } from "vue";
import type { Router } from "vue-router";
import { showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import TaskEvidenceSection from "@/components/evidence/TaskEvidenceSection.vue";
import TaskContributionGovernance from "@/components/contributions/TaskContributionGovernance.vue";
import TaskExpectedShareConsent from "@/components/contributions/TaskExpectedShareConsent.vue";
import FileWithdrawalPanel from "@/components/files/FileWithdrawalPanel.vue";
import TaskDispositionAction from "@/components/task/TaskDispositionAction.vue";
import TaskNudgeAction from "@/components/reminders/TaskNudgeAction.vue";
import TaskReminderPreferences from "@/components/reminders/TaskReminderPreferences.vue";
import FilePreviewPanel from "@/components/file/FilePreviewPanel.vue";
import TaskCollaborators from "@/components/task/TaskCollaborators.vue";
import TaskHelpPanel from "@/components/task/TaskHelpPanel.vue";
import TaskReviewHistory from "@/components/task/TaskReviewHistory.vue";
import TaskSubmissionPanel from "@/components/task/TaskSubmissionPanel.vue";
import UpstreamArtifacts from "@/components/task/UpstreamArtifacts.vue";
import UpstreamReworkPanel from "@/components/task/UpstreamReworkPanel.vue";
import TaskDependenciesSection from "@/components/task-detail/TaskDependenciesSection.vue";
import TaskDetailAlerts from "@/components/task-detail/TaskDetailAlerts.vue";
import TaskDetailHeader from "@/components/task-detail/TaskDetailHeader.vue";
import TaskDetailSection from "@/components/task-detail/TaskDetailSection.vue";
import TaskFilesSection from "@/components/task-detail/TaskFilesSection.vue";
import TaskHistorySection from "@/components/task-detail/TaskHistorySection.vue";
import TaskOverviewSection from "@/components/task-detail/TaskOverviewSection.vue";
import { useTaskDetailLegacyController } from "@/composables/useTaskDetailLegacyController";
import {
  selectTaskCurrentAction,
  taskDetailAlerts,
} from "@/domain/task-current-action";
import { displayStatusLabel } from "@/domain/presentation-labels";
import {
  normalizeRequiredSubmissionFileTypes,
  SUBMISSION_FILE_TYPE_OPTIONS,
  type SubmissionFileType,
} from "@/domain/submission-file-types";
import {
  invokeDisposition,
  type TaskDispositionCommand,
} from "@/features/task-disposition/repository";
import {
  createDownloadUrl,
  openDownload,
  type PreviewFileVersion,
} from "@/services/file-preview";
import type { TaskCurrentAction } from "@/types/frontend-integration";
import type { TaskFileVersion } from "@/types/ui";

const props = defineProps<{
  projectId: string;
  taskId: string;
  compact?: boolean;
}>();

const router = getCurrentInstance()?.appContext.config.globalProperties
  .$router as Router | undefined;
const controller = useTaskDetailLegacyController(props);

const {
  workspace,
  workflow,
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
} = controller;

function toggleEditRequiredFileType(type: SubmissionFileType) {
  const next = editRequiredFileTypes.value.includes(type)
    ? editRequiredFileTypes.value.filter((item) => item !== type)
    : [...editRequiredFileTypes.value, type];
  editRequiredFileTypes.value = normalizeRequiredSubmissionFileTypes(next);
  editDirty.value = true;
}

function toggleProposalRequiredFileType(type: SubmissionFileType) {
  const next = proposalRequiredFileTypes.value.includes(type)
    ? proposalRequiredFileTypes.value.filter((item) => item !== type)
    : [...proposalRequiredFileTypes.value, type];
  proposalRequiredFileTypes.value = normalizeRequiredSubmissionFileTypes(next);
}

const previewVersionId = ref<string | null>(null);
const requestedSection = ref<string | null>(null);
const archived = computed(() => !!workspace.project?.archived_at);
const activeTask = computed(
  () =>
    !!task.value &&
    !["awaiting_review", "completed", "canceled"].includes(
      String(task.value.status),
    ),
);
const manageEvidence = computed(
  () => workspace.role === "leader" || workspace.role === "admin",
);
const canWriteEvidence = computed(
  () =>
    !archived.value &&
    activeTask.value &&
    !!workspace.membership &&
    workspace.role !== "observer",
);
const canNudge = computed(() => canWriteEvidence.value && manageEvidence.value);
const evidenceMemberNames = computed<Record<string, string>>(() =>
  Object.fromEntries(
    (workspace.members ?? [])
      .filter((member) => member.user_id)
      .map((member) => [member.user_id!, workspace.memberName(member.user_id)]),
  ),
);
const shareParticipants = computed(() => {
  const current = task.value;
  if (!current) return [];
  const ids = [
    current.assignee_id,
    ...(workspace.collaboratorsForTask?.(current.id) ?? [])
      .filter((member) => member.state === "accepted")
      .map((member) => member.user_id),
  ].filter((userId): userId is string => !!userId);
  return [...new Set(ids)].map((userId) => ({
    userId,
    name: workspace.memberName(userId),
  }));
});
const canWriteContribution = computed(
  () =>
    !archived.value &&
    workspace.project?.lifecycle_state === "active" &&
    !!workspace.membership &&
    workspace.role !== "observer",
);
const canDisposeTask = computed(
  () =>
    canWriteContribution.value &&
    !!task.value &&
    (workspace.role === "leader" ||
      task.value.created_by === workspace.currentUserId),
);
const canCancelTask = computed(
  () =>
    canDisposeTask.value &&
    !!task.value &&
    ["not_started", "in_progress", "blocked"].includes(task.value.status),
);
const canDeleteTask = computed(
  () =>
    canDisposeTask.value &&
    !!task.value &&
    task.value.version === 1 &&
    task.value.status === "not_started" &&
    task.value.assignee_id === null,
);
const canAbandonTask = computed(
  () =>
    canWriteContribution.value &&
    isAssignee.value &&
    !!task.value?.accepted_at &&
    !!task.value &&
    ["in_progress", "blocked"].includes(task.value.status),
);
const dispositionRetry = ref<{ fingerprint: string; requestId: string } | null>(
  null,
);
async function performDisposition(
  command: TaskDispositionCommand,
  reason?: string,
): Promise<void> {
  if (!task.value || !canWriteContribution.value)
    throw new Error("项目当前不可编辑");
  if (command === "cmd_cancel_task" && !canCancelTask.value)
    throw new Error("无权取消任务");
  if (command === "cmd_delete_empty_task" && !canDeleteTask.value)
    throw new Error("任务有不可删除的历史");
  if (command === "cmd_abandon_task_responsibility" && !canAbandonTask.value)
    throw new Error("当前不具备放弃资格");
  const fingerprint = JSON.stringify({
    command,
    taskId: task.value.id,
    version: task.value.version,
    reason: reason ?? null,
  });
  if (dispositionRetry.value?.fingerprint !== fingerprint)
    dispositionRetry.value = { fingerprint, requestId: crypto.randomUUID() };
  await invokeDisposition(command, {
    p_project_id: props.projectId,
    p_task_id: props.taskId,
    ...(reason === undefined ? {} : { p_reason: reason }),
    p_expected_version: task.value.version,
    p_request_id: dispositionRetry.value.requestId,
  });
  dispositionRetry.value = null;
  showToast(
    command === "cmd_cancel_task"
      ? "任务已取消"
      : command === "cmd_delete_empty_task"
        ? "空任务已删除"
        : "已放弃责任",
  );
  if (command === "cmd_delete_empty_task" && router) {
    await router.push({
      name: "project-tasks",
      params: { projectId: props.projectId },
    });
  } else {
    await refresh();
  }
}

const collaboratorPresentations = computed(() =>
  task.value
    ? (workspace.collaboratorsForTask?.(task.value.id) ?? [])
        .filter((item) => ["pending", "accepted"].includes(item.state))
        .map((item) => ({
          id: item.id,
          name: item.user_name_snapshot || workspace.memberName(item.user_id),
          state:
            item.state === "accepted"
              ? ("accepted" as const)
              : ("pending" as const),
        }))
    : [],
);

const acceptedCollaboratorNames = computed(() =>
  collaboratorPresentations.value
    .filter((item) => item.state === "accepted")
    .map((item) => item.name),
);

const pendingCollaborationInvite = computed(
  () => workspace.findCollaborator?.(props.taskId)?.state === "pending",
);
const isAcceptedCollaborator = computed(
  () => workspace.isAcceptedCollaborator?.(props.taskId) ?? false,
);
const activeIssueCount = computed(
  () =>
    (workflow?.helpRequests ?? []).filter((item) => item.state === "open")
      .length +
    (workflow?.reworkRequests ?? []).filter((item) => item.state === "pending")
      .length,
);

const canFinalSubmit = computed(
  () =>
    isAssignee.value &&
    task.value?.assignment_state === "assigned" &&
    !!task.value &&
    ["in_progress", "blocked"].includes(task.value.status),
);

const currentAction = computed(() =>
  selectTaskCurrentAction({
    pendingChangeConfirmation: canDecideTaskChange.value,
    pendingCollaborationInvite: pendingCollaborationInvite.value,
    canReview: canReview.value,
    isPrimary: isAssignee.value,
    needsChanges: !!rejectedReason.value,
    canFinalSubmit: canFinalSubmit.value,
    isAcceptedCollaborator: isAcceptedCollaborator.value,
    canUpload: canUploadTaskFile.value,
  }),
);

const alerts = computed(() =>
  taskDetailAlerts({
    needsChanges: !!rejectedReason.value,
    rejectionReason: rejectedReason.value,
    waitingUpstream:
      dependencyState.value.blocked && !task.value?.first_submitted_at,
    pendingCollaborationInvite: pendingCollaborationInvite.value,
    pendingChangeConfirmation: canDecideTaskChange.value,
    activeIssueCount: activeIssueCount.value,
  }),
);

const previewedVersion = computed(
  () =>
    versions.value.find(
      (version) => version.fileVersionId === previewVersionId.value,
    ) ?? null,
);

function previewVersion(version: TaskFileVersion): PreviewFileVersion {
  return {
    id: version.fileVersionId,
    originalName: version.originalName,
    mimeType: version.mimeType,
    sizeBytes: version.sizeBytes,
    versionNumber: version.versionNumber,
    uploadedBy: version.uploadedBy,
    createdAt: version.createdAt,
  };
}

function openTaskVersion(version: TaskFileVersion) {
  previewVersionId.value = version.fileVersionId;
}

async function downloadTaskVersion(version: TaskFileVersion) {
  try {
    const result = await openDownload(
      await createDownloadUrl(props.projectId, version.fileVersionId),
      version.originalName,
      version.mimeType,
    );
    if (result?.native) showToast("已加入系统下载");
  } catch {
    showToast("无法生成下载链接");
  }
}

async function handleCurrentAction(action: TaskCurrentAction) {
  if (action.kind === "open-review" && latestReview.value && router) {
    await router.push({
      name: "review-detail",
      params: {
        projectId: props.projectId,
        reviewRoundId: latestReview.value.id,
      },
    });
    return;
  }

  const targetId =
    action.kind === "confirm-change"
      ? "task-history-section"
      : action.kind === "respond-collaboration"
        ? "task-issues-section"
        : "task-submission-section";
  document.getElementById(targetId)?.scrollIntoView({
    block: "start",
    behavior: "smooth",
  });
}

function scrollToRequestedSection(section: string | null) {
  const target =
    section === "upstream-artifacts"
      ? "task-upstream-section"
      : section === "collaboration-issues"
        ? "task-issues-section"
        : section === "changes"
          ? "task-history-section"
          : section === "submission"
            ? "task-submission-section"
            : null;
  if (!target || requestedSection.value === section) return;
  requestedSection.value = section;
  requestAnimationFrame(() =>
    document.getElementById(target)?.scrollIntoView({ block: "start" }),
  );
}

watch(
  () => router?.currentRoute.value.query.section,
  (section) =>
    scrollToRequestedSection(typeof section === "string" ? section : null),
  { immediate: true },
);
</script>

<template>
  <section class="task-detail" :class="{ compact }">
    <PageState
      :loading="workspace.loading && !task"
      :error="workspace.error"
      :not-found-or-denied="!workspace.project || !workspace.membership"
      :empty="!workspace.loading && !task"
      empty-title="找不到这个任务"
      @retry="refresh"
    >
      <template v-if="task">
        <TaskDetailHeader
          :title="task.title"
          :status="displayStatusLabel(workspace.taskDisplayStatus(task))"
          :primary-name="workspace.memberName(task.assignee_id)"
          :collaborator-names="acceptedCollaboratorNames"
          :deadline-at="task.deadline_at"
          :weight="task.weight"
          :current-action="currentAction"
          :compact="compact"
          @action="handleCurrentAction"
        />

        <div v-if="workspace.actionError" class="error-banner" role="alert">
          {{ workspace.actionError }}
        </div>

        <TaskDetailAlerts :alerts="alerts" />

        <div class="task-sections">
          <TaskDetailSection title="概况" default-open>
            <TaskOverviewSection
              :description="task.description"
              :status="displayStatusLabel(workspace.taskDisplayStatus(task))"
              :deadline-at="task.deadline_at"
              :weight="task.weight"
              :primary-name="workspace.memberName(task.assignee_id)"
              :collaborators="collaboratorPresentations"
            >
              <TaskCollaborators :task="task" />

              <section v-if="canEditTask" class="inline-editor">
                <div class="subheading">
                  <strong>任务信息</strong>
                  <van-button
                    size="small"
                    type="primary"
                    :loading="workspace.pendingAction === 'edit-task'"
                    @click="saveTaskBasics"
                  >
                    保存
                  </van-button>
                </div>
                <div class="edit-grid">
                  <label class="wide">
                    <span>标题</span>
                    <input
                      v-model="editTitle"
                      maxlength="240"
                      @input="editDirty = true"
                    />
                  </label>
                  <label class="wide">
                    <span>描述</span>
                    <textarea
                      v-model="editDescription"
                      rows="3"
                      maxlength="4000"
                      @input="editDirty = true"
                    />
                  </label>
                  <label>
                    <span>截止时间</span>
                    <input
                      v-model="editDeadlineAt"
                      type="datetime-local"
                      :disabled="definitionLocked"
                      @input="editDirty = true"
                    />
                  </label>
                  <label
                    v-if="workspace.project?.contribution_mode === 'weighted'"
                  >
                    <span>难度</span>
                    <select
                      v-model.number="editWeight"
                      :disabled="definitionLocked"
                      @change="editDirty = true"
                    >
                      <option v-for="value in 5" :key="value" :value="value">
                        {{ value }} 星
                      </option>
                    </select>
                  </label>
                  <fieldset class="file-type-requirement">
                    <legend>提交文件类型（可多选）</legend>
                    <label
                      v-for="option in SUBMISSION_FILE_TYPE_OPTIONS"
                      :key="option.value"
                      class="file-type-choice"
                    >
                      <input
                        type="checkbox"
                        :checked="editRequiredFileTypes.includes(option.value)"
                        :disabled="definitionLocked"
                        @change="toggleEditRequiredFileType(option.value)"
                      />
                      <span>{{ option.label }}</span>
                    </label>
                    <p class="field-note">
                      {{
                        editRequiredFileTypes.length
                          ? "提交附件至少包含其中一种即可。"
                          : "不限制文件类型。"
                      }}
                    </p>
                  </fieldset>
                </div>
              </section>

              <div v-if="!archived" class="task-followup-reminders">
                <TaskReminderPreferences
                  v-if="isParticipant && activeTask"
                  :project-id="projectId"
                  :task-id="taskId"
                />
                <TaskNudgeAction
                  :project-id="projectId"
                  :task-id="taskId"
                  :task-version="task.version"
                  :can-nudge="canNudge"
                  @sent="refresh"
                />
              </div>

              <TaskExpectedShareConsent
                v-if="workspace.project?.contribution_mode === 'weighted'"
                :project-id="projectId"
                :task-id="taskId"
                :task-version="task.version"
                :accepted-at="task.accepted_at"
                :task-weight="task.weight"
                :deadline-at="task.deadline_at"
                :can-consent="
                  canWriteContribution &&
                  (isAssignee || canRespond || pendingCollaborationInvite)
                "
                :auto-penalty-enabled="
                  !!workspace.project?.auto_penalty_enabled
                "
                :user-id="workspace.currentUserId"
                @consented="refresh"
              />
              <div class="section-divider" />
              <section class="participant-actions">
                <div class="action-row">
                  <van-button
                    v-if="
                      task.assignment_state === 'claimable' &&
                      workspace.role !== 'observer' &&
                      !isAcceptedCollaborator
                    "
                    type="primary"
                    :loading="workspace.pendingAction === 'claim-task'"
                    @click="claim"
                  >
                    认领任务
                  </van-button>
                  <template
                    v-if="
                      task.assignment_state === 'pending_acceptance' &&
                      canRespond
                    "
                  >
                    <van-button
                      type="primary"
                      :loading="workspace.pendingAction === 'assignment'"
                      @click="respond('accept')"
                    >
                      接受指派
                    </van-button>
                    <van-button
                      plain
                      :loading="workspace.pendingAction === 'assignment'"
                      @click="respond('reject')"
                    >
                      拒绝指派
                    </van-button>
                  </template>
                </div>

                <div
                  v-if="isParticipant && task.assignment_state === 'assigned'"
                  class="progress-editor"
                >
                  <van-field
                    v-model="progressText"
                    label="工作记录"
                    type="textarea"
                    rows="2"
                    maxlength="500"
                    show-word-limit
                    placeholder="记录当前进展，不填写百分比"
                  />
                  <van-field
                    v-model="blockedReason"
                    label="阻塞原因"
                    placeholder="仅在标记阻塞时必填"
                  />
                  <div class="action-row">
                    <van-button
                      size="small"
                      type="primary"
                      plain
                      @click="saveProgress('in_progress')"
                    >
                      更新进行状态
                    </van-button>
                    <van-button
                      size="small"
                      type="danger"
                      plain
                      @click="saveProgress('blocked')"
                    >
                      标记阻塞
                    </van-button>
                  </div>
                </div>
              </section>
            </TaskOverviewSection>
          </TaskDetailSection>

          <div id="task-submission-section">
            <TaskDetailSection title="提交与文件" default-open>
              <div class="submission-files-grid">
                <p
                  v-if="dependencyState.blocked && !task.first_submitted_at"
                  class="capability-note"
                >
                  上游任务尚未完成，仍可以先提交和完成下游成果。
                </p>

                <TaskSubmissionPanel
                  v-if="
                    isAssignee &&
                    task.assignment_state === 'assigned' &&
                    ['in_progress', 'blocked'].includes(task.status)
                  "
                  :versions="versions"
                  :required-file-types="requiredSubmissionFileTypes"
                  :dependency-blocked="dependencyState.blocked"
                  :requires-review="task.requires_review"
                  :submit-loading="workspace.pendingAction === 'submit-review'"
                  :upload-loading="workspace.pendingAction === 'file-upload'"
                  :reset-key="submissionResetKey"
                  :auto-select-file-version-id="
                    submissionAutoSelectFileVersionId
                  "
                  @upload="performUpload"
                  @submit="submitReview"
                />
                <p v-else-if="isAcceptedCollaborator" class="capability-note">
                  你以协作者身份参与此任务，可以上传任务文件；最终提交验收由主负责人执行。
                </p>

                <div class="section-divider" />
                <TaskFilesSection
                  :files="taskFiles"
                  :can-upload="canUploadTaskFile"
                  :busy="workspace.pendingAction === 'file-upload'"
                  @upload="chooseUpload"
                  @preview="openTaskVersion"
                  @download="downloadTaskVersion"
                />
                <FileWithdrawalPanel
                  :project-id="projectId"
                  :task-id="taskId"
                  :files="taskFiles"
                  :user-id="workspace.currentUserId"
                  :is-leader="workspace.role === 'leader'"
                  :can-manage="canWriteContribution"
                  @changed="refresh"
                />
                <input
                  ref="uploadInput"
                  class="sr-only"
                  type="file"
                  aria-label="上传任务文件"
                  @change="upload"
                />
                <van-button
                  v-if="failedUploadFile"
                  size="small"
                  plain
                  :loading="workspace.pendingAction === 'file-upload'"
                  @click="retryUpload"
                >
                  重试 {{ failedUploadFile.name }}
                </van-button>

                <FilePreviewPanel
                  v-if="previewedVersion"
                  :project-id="props.projectId"
                  :file-version="previewVersion(previewedVersion)"
                  :uploader-name="
                    workspace.memberName(previewedVersion.uploadedBy)
                  "
                  @close="previewVersionId = null"
                />

                <div class="section-divider" />
                <TaskEvidenceSection
                  :project-id="projectId"
                  :task-id="taskId"
                  :task-version="task.version"
                  :can-write="canWriteEvidence"
                  :can-manage="manageEvidence"
                  :user-id="workspace.currentUserId"
                  :member-names="evidenceMemberNames"
                />

                <div class="section-divider" />
                <TaskReviewHistory
                  :rounds="taskReviews"
                  :round-files="taskReviewFiles"
                  :versions="versions"
                />

                <p
                  v-if="
                    latestReview?.state === 'pending' &&
                    latestReview.delegation_required
                  "
                  class="capability-note"
                  role="status"
                >
                  <template v-if="latestReview.delegated_reviewer_id">
                    本轮已委派独立验收人：{{
                      workspace.memberName(latestReview.delegated_reviewer_id)
                    }}。
                  </template>
                  <template v-else>
                    当前没有可用的独立验收人，任务仍待验收。请邀请合格的项目成员加入。
                  </template>
                </p>

                <div
                  v-if="canReview && workspace.capabilities.canReviewSubmission"
                  class="review-actions"
                >
                  <van-field
                    v-model="blockedReason"
                    label="验收意见"
                    type="textarea"
                    rows="2"
                    placeholder="要求修改时必填"
                  />
                  <div class="action-row">
                    <van-button
                      type="primary"
                      :loading="workspace.pendingAction === 'review'"
                      @click="review('approve')"
                    >
                      通过
                    </van-button>
                    <van-button
                      type="danger"
                      plain
                      :loading="workspace.pendingAction === 'review'"
                      @click="review('request_changes')"
                    >
                      要求修改
                    </van-button>
                  </div>
                </div>
              </div>
            </TaskDetailSection>
          </div>

          <div id="task-upstream-section">
            <TaskDetailSection title="上下游">
              <TaskDependenciesSection
                :upstream-tasks="upstreamTasks"
                :downstream-tasks="downstreamTasks"
                :blocked="dependencyState.blocked && !task.first_submitted_at"
                :incomplete-upstream-count="
                  dependencyState.incompleteUpstreamCount
                "
                :effective-start-at="dependencyState.effectiveStartAt"
                :can-edit="canEditTask"
              >
                <div v-if="canEditTask" class="dependency-editor">
                  <strong>管理直接上游</strong>
                  <label
                    v-for="candidate in dependencyCandidates"
                    :key="candidate.id"
                  >
                    <input
                      v-model="selectedUpstreamTaskIds"
                      type="checkbox"
                      :value="candidate.id"
                      @change="dependencyDirty = true"
                    />
                    {{ candidate.title }} ·
                    {{
                      displayStatusLabel(workspace.taskDisplayStatus(candidate))
                    }}
                  </label>
                  <van-button
                    size="small"
                    type="primary"
                    plain
                    :loading="workspace.pendingAction === 'task-dependencies'"
                    @click="saveDependencies"
                  >
                    保存上游
                  </van-button>
                </div>
              </TaskDependenciesSection>

              <UpstreamArtifacts
                v-if="upstreamTasks.length"
                :project-id="props.projectId"
                :task-id="props.taskId"
              />
            </TaskDetailSection>
          </div>

          <div id="task-issues-section">
            <TaskDetailSection
              title="协作与问题"
              :badge="activeIssueCount || null"
              :default-open="activeIssueCount > 0"
            >
              <div class="issue-grid">
                <TaskHelpPanel :project-id="projectId" :task-id="taskId" />
                <div class="section-divider" />
                <UpstreamReworkPanel
                  :project-id="projectId"
                  :task-id="taskId"
                />
              </div>
            </TaskDetailSection>
          </div>

          <div id="task-history-section">
            <TaskDetailSection title="历史与变更">
              <TaskHistorySection
                :reviews="taskReviews"
                :change-proposal="taskChangeProposal"
                :can-decide-change="canDecideTaskChange"
              >
                <template #change-actions>
                  <template v-if="pendingTaskChange && canDecideTaskChange">
                    <van-field
                      v-model="rejectionReason"
                      label="拒绝理由"
                      maxlength="1000"
                      placeholder="可选"
                    />
                    <div class="action-row">
                      <van-button
                        type="primary"
                        :loading="
                          workspace.pendingAction === 'task-change-decision'
                        "
                        @click="decideImportantChange('approve')"
                      >
                        批准
                      </van-button>
                      <van-button
                        plain
                        type="danger"
                        :loading="
                          workspace.pendingAction === 'task-change-decision'
                        "
                        @click="decideImportantChange('reject')"
                      >
                        拒绝
                      </van-button>
                    </div>
                  </template>
                </template>

                <section
                  v-if="canProposeTaskChange && !pendingTaskChange"
                  class="change-proposal"
                >
                  <strong>发起重要变更确认</strong>
                  <p class="capability-note">
                    已有任务活动后，截止时间、难度和提交必需文件类型的变更先进入确认流程，不会直接覆盖当前值。
                  </p>
                  <div class="edit-grid">
                    <label>
                      <span>新截止时间</span>
                      <input
                        v-model="proposalDeadlineAt"
                        type="datetime-local"
                      />
                    </label>
                    <label
                      v-if="workspace.project?.contribution_mode === 'weighted'"
                    >
                      <span>新难度</span>
                      <select v-model.number="proposalWeight">
                        <option v-for="value in 5" :key="value" :value="value">
                          {{ value }} 星
                        </option>
                      </select>
                    </label>
                    <fieldset class="file-type-requirement">
                      <legend>新的提交文件类型（可多选）</legend>
                      <label
                        v-for="option in SUBMISSION_FILE_TYPE_OPTIONS"
                        :key="option.value"
                        class="file-type-choice"
                      >
                        <input
                          type="checkbox"
                          :checked="
                            proposalRequiredFileTypes.includes(option.value)
                          "
                          @change="toggleProposalRequiredFileType(option.value)"
                        />
                        <span>{{ option.label }}</span>
                      </label>
                      <p class="field-note">
                        {{
                          proposalRequiredFileTypes.length
                            ? "提交附件至少包含其中一种即可。"
                            : "不限制文件类型。"
                        }}
                      </p>
                    </fieldset>
                  </div>
                  <van-button
                    size="small"
                    type="primary"
                    :loading="
                      workspace.pendingAction === 'task-change-proposal'
                    "
                    @click="proposeImportantChange"
                  >
                    发起变更确认
                  </van-button>
                </section>
              </TaskHistorySection>
              <div class="section-divider" />
              <TaskContributionGovernance
                :project-id="projectId"
                :task-id="taskId"
                :task-version="task.version"
                :participants="shareParticipants"
                :user-id="workspace.currentUserId"
                :is-primary="isAssignee"
                :task-completed="task.status === 'completed'"
                :can-write="canWriteContribution"
                @changed="refresh"
              />
              <div class="section-divider" />
              <TaskDispositionAction
                :can-cancel="canCancelTask"
                :can-abandon="canAbandonTask"
                :can-delete="canDeleteTask"
                :on-cancel="
                  (reason) => performDisposition('cmd_cancel_task', reason)
                "
                :on-abandon="
                  (reason) =>
                    performDisposition(
                      'cmd_abandon_task_responsibility',
                      reason,
                    )
                "
                :on-delete="() => performDisposition('cmd_delete_empty_task')"
              />
            </TaskDetailSection>
          </div>
        </div>
      </template>
    </PageState>
  </section>
</template>

<style scoped>
.task-detail {
  display: grid;
  gap: var(--space-md);
  min-width: 0;
  width: 100%;
  padding: 0;
}
.task-detail.compact {
  padding: 14px;
}
.task-sections,
.submission-files-grid,
.inline-editor,
.participant-actions,
.progress-editor,
.dependency-editor,
.change-proposal,
.issue-grid {
  display: grid;
  gap: 12px;
}
.submission-files-grid {
  padding-top: 16px;
}
.inline-editor,
.participant-actions,
.dependency-editor,
.change-proposal {
  padding-top: 14px;
  border-top: 1px solid var(--tu-border);
}
.section-divider {
  height: 1px;
  background: var(--tu-border);
}
.subheading,
.action-row {
  display: flex;
  justify-content: space-between;
  gap: 10px;
  align-items: center;
  flex-wrap: wrap;
}
.edit-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}
.edit-grid label {
  display: grid;
  gap: 5px;
  color: var(--tu-muted);
  font-size: 13px;
}
.edit-grid .wide {
  grid-column: 1 / -1;
}
.file-type-requirement {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
  min-width: 0;
  margin: 0;
  padding: 0;
  border: 0;
  grid-column: 1 / -1;
}
.file-type-requirement legend {
  grid-column: 1 / -1;
  margin-bottom: 8px;
  color: var(--tu-ink);
  font-size: 13px;
  font-weight: 650;
}
.edit-grid .file-type-choice {
  display: flex;
  align-items: center;
  gap: 7px;
  color: var(--tu-ink);
  font-size: 13px;
}
.edit-grid .file-type-choice input {
  width: auto;
  min-height: 0;
}
.file-type-requirement .field-note {
  grid-column: 1 / -1;
  margin: 0;
  color: var(--tu-muted);
  font-size: 12px;
}
.edit-grid input,
.edit-grid textarea,
.edit-grid select {
  width: 100%;
  min-height: 40px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-subtle-surface);
  color: var(--tu-ink);
  padding: 8px 9px;
  font: inherit;
}
.edit-grid textarea {
  resize: vertical;
}
.dependency-editor label {
  display: flex;
  gap: 8px;
  align-items: center;
}
.review-actions {
  display: grid;
  gap: 10px;
}
.error-banner {
  padding: 12px 14px;
  border-radius: 10px;
  background: var(--tu-danger-surface);
  color: var(--tu-danger-ink);
}
@media (max-width: 700px) {
  .task-detail.compact {
    padding: var(--space-sm);
  }
  .edit-grid {
    grid-template-columns: 1fr;
  }
  .edit-grid .wide {
    grid-column: auto;
  }
}
</style>
