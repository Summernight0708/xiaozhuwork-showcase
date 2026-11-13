<script setup lang="ts">
import ContextHelpLink from "@/components/help/ContextHelpLink.vue";
defineOptions({ name: "ProjectReviewsView" });

import { computed, onActivated, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { showConfirmDialog, showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import FilePreviewPanel from "@/components/file/FilePreviewPanel.vue";
import ReviewQueue from "@/components/review/ReviewQueue.vue";
import ReviewSubmissionDetail from "@/components/review/ReviewSubmissionDetail.vue";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import {
  buildReviewSnapshot,
  matchesReviewQueue,
  reviewHistoryForTask,
  type ReviewQueueFilter,
} from "@/domain/review-center";
import {
  canCorrectReviewRequestChanges,
  canRequestChangesOnReview,
  canReviewTaskSubmission,
} from "@/domain/task-review";
import {
  createDownloadUrl,
  openDownload,
  type PreviewFileVersion,
} from "@/services/file-preview";
import type { TaskFileVersion } from "@/types/ui";
import type {
  ReviewAttachmentSnapshot,
  ReviewRoundSnapshot,
} from "@/types/frontend-integration";

const route = useRoute();
const router = useRouter();
const { workspace, reload } = useWorkspaceRoute();

const tab = ref<ReviewQueueFilter>("pending");
const memberFilter = ref("all");
const selectedId = ref<string | null>(
  typeof route.params.reviewRoundId === "string"
    ? route.params.reviewRoundId
    : null,
);
const reviewsLoaded = ref(false);
const previewVersion = ref<TaskFileVersion | null>(null);

const snapshots = computed<ReviewRoundSnapshot[]>(() =>
  workspace.reviews.flatMap((round) => {
    const task = workspace.findTask(round.task_id);
    if (!task) return [];
    return [
      buildReviewSnapshot({
        round,
        roundFiles: workspace.reviewFiles ?? [],
        task,
        taskFiles: workspace.taskFiles[round.task_id] ?? [],
        memberName: workspace.memberName,
      }),
    ];
  }),
);

const visible = computed(() =>
  snapshots.value.filter(
    (snapshot) =>
      matchesReviewQueue(snapshot, tab.value) &&
      (memberFilter.value === "all" ||
        snapshot.submitterId === memberFilter.value),
  ),
);

const routedReviewId = computed(() =>
  typeof route.params.reviewRoundId === "string"
    ? route.params.reviewRoundId
    : null,
);

const selected = computed(
  () =>
    snapshots.value.find((round) => round.id === routedReviewId.value) ??
    visible.value.find((round) => round.id === selectedId.value) ??
    visible.value[0] ??
    null,
);

const selectedRaw = computed(() =>
  selected.value
    ? (workspace.reviews.find((round) => round.id === selected.value!.id) ??
      null)
    : null,
);

const selectedTask = computed(() =>
  selected.value ? workspace.findTask(selected.value.taskId) : null,
);

const selectedHistory = computed(() =>
  selected.value
    ? reviewHistoryForTask(snapshots.value, selected.value.taskId)
    : [],
);

const canAct = computed(
  () =>
    !!selectedRaw.value &&
    !!selectedTask.value &&
    canReviewTaskSubmission({
      role: workspace.role,
      currentUserId: workspace.currentUserId,
      task: selectedTask.value,
      round: selectedRaw.value,
    }),
);
const canRequestChanges = computed(
  () =>
    !!selectedRaw.value &&
    !!selectedTask.value &&
    canRequestChangesOnReview({
      role: workspace.role,
      currentUserId: workspace.currentUserId,
      task: selectedTask.value,
      round: selectedRaw.value,
      downstreamTasks: workspace.downstreamTasks(selectedTask.value.id),
    }),
);

const canCorrect = computed(() => {
  if (!selectedRaw.value || !selectedTask.value) return false;
  const latestRound = workspace.reviews
    .filter((round) => round.task_id === selectedRaw.value!.task_id)
    .sort((left, right) => right.round_number - left.round_number)[0];
  return canCorrectReviewRequestChanges({
    role: workspace.role,
    currentUserId: workspace.currentUserId,
    task: selectedTask.value,
    round: selectedRaw.value,
    isLatestRound: latestRound?.id === selectedRaw.value.id,
  });
});

const invalidReviewDeepLink = computed(
  () =>
    reviewsLoaded.value && !!routedReviewId.value && selected.value === null,
);

async function load() {
  reviewsLoaded.value = false;
  await workspace.loadReviews();
  const taskIds = [...new Set(workspace.reviews.map((round) => round.task_id))];
  await Promise.all(taskIds.map((taskId) => workspace.loadTaskFiles(taskId)));
  reviewsLoaded.value = true;
  if (!selectedId.value && visible.value.length) {
    selectedId.value = visible.value[0]!.id;
  }
}

async function select(round: ReviewRoundSnapshot) {
  selectedId.value = round.id;
  await router.push({
    name: "review-detail",
    params: {
      projectId: String(route.params.projectId),
      reviewRoundId: round.id,
    },
  });
}

async function backToQueue() {
  selectedId.value = null;
  await router.replace({
    name: "project-reviews",
    params: { projectId: String(route.params.projectId) },
  });
}

function taskFileVersion(attachment: ReviewAttachmentSnapshot) {
  if (!selected.value) return null;
  for (const file of workspace.taskFiles[selected.value.taskId] ?? []) {
    const version = file.versions.find(
      (candidate) => candidate.fileVersionId === attachment.fileVersionId,
    );
    if (version) return version;
  }
  return null;
}

function openPreview(attachment: ReviewAttachmentSnapshot) {
  previewVersion.value = taskFileVersion(attachment);
  if (!previewVersion.value) showToast("历史文件版本不可用");
}

async function downloadAttachment(attachment: ReviewAttachmentSnapshot) {
  try {
    const version = taskFileVersion(attachment);
    const result = await openDownload(
      await createDownloadUrl(
        String(route.params.projectId),
        attachment.fileVersionId,
      ),
      version?.originalName,
      version?.mimeType,
    );
    if (result?.native) showToast("已加入系统下载");
  } catch {
    showToast("无法生成下载链接");
  }
}

function asPreviewFileVersion(version: TaskFileVersion): PreviewFileVersion {
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

async function approve() {
  if (!selectedRaw.value || !selectedTask.value) return;
  try {
    const result = await workspace.reviewSubmission(
      selectedTask.value,
      selectedRaw.value,
      "approve",
    );
    showToast(
      result.ok
        ? "验收已通过，任务已完成"
        : workspace.actionError || "验收操作失败",
    );
  } catch {
    showToast(workspace.actionError || "验收结果同步失败，请刷新核对");
  }
}

async function requestChanges(reason: string) {
  if (!selectedRaw.value || !selectedTask.value) return;
  try {
    const result = await workspace.reviewSubmission(
      selectedTask.value,
      selectedRaw.value,
      "request_changes",
      reason,
    );
    showToast(
      result.ok ? "已要求修改" : workspace.actionError || "验收操作失败",
    );
  } catch {
    showToast(workspace.actionError || "验收结果同步失败，请刷新核对");
  }
}

async function correctRequestChanges() {
  if (!selectedRaw.value || !selectedTask.value || !canCorrect.value) return;
  try {
    await showConfirmDialog({
      title: "纠正误打回？",
      message: "原验收记录不会被修改；系统会为同一份提交新增一轮待验收记录。",
      confirmButtonText: "确认纠正",
    });
  } catch {
    return;
  }
  const result = await workspace.correctReviewRequestChanges(
    selectedTask.value,
    selectedRaw.value,
  );
  showToast(
    result.ok
      ? "已纠正误打回，原提交重新进入待验收"
      : workspace.actionError || "纠正失败",
  );
}

watch(
  () => route.params.reviewRoundId,
  (reviewRoundId) => {
    selectedId.value = typeof reviewRoundId === "string" ? reviewRoundId : null;
  },
);

watch(tab, () => {
  if (!routedReviewId.value) selectedId.value = visible.value[0]?.id ?? null;
});

onActivated(() => void load());
void load();
</script>

<template>
  <div class="xiaozhuwork-page">
    <header class="page-heading">
      <div>
        <div class="page-title-line">
          <h1>验收</h1>
          <ContextHelpLink example-id="review" />
        </div>
      </div>
    </header>

    <div class="review-toolbar">
      <div class="review-tabs" role="tablist" aria-label="验收队列">
        <button
          type="button"
          :class="{ active: tab === 'pending' }"
          @click="tab = 'pending'"
        >
          待处理
        </button>
        <button
          type="button"
          :class="{ active: tab === 'processed' }"
          @click="tab = 'processed'"
        >
          已处理
        </button>
      </div>
      <select v-model="memberFilter" aria-label="成员筛选">
        <option value="all">全部成员</option>
        <option
          v-for="member in workspace.members"
          :key="member.id"
          :value="member.user_id || ''"
        >
          {{ member.display_name_snapshot || "未命名成员" }}
        </option>
      </select>
    </div>

    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="
        !workspace.project || !workspace.membership || invalidReviewDeepLink
      "
      :empty="!visible.length && !selected"
      empty-title="当前没有验收事项"
      @retry="
        async () => {
          await reload();
          await load();
        }
      "
    >
      <p
        v-if="
          selectedRaw?.state === 'pending' && selectedRaw.delegation_required
        "
        class="muted"
        role="status"
      >
        <template v-if="selectedRaw.delegated_reviewer_id">
          本轮独立验收人：{{
            workspace.memberName(selectedRaw.delegated_reviewer_id)
          }}
        </template>
        <template v-else>
          当前暂无可用的独立验收人；须先邀请合格成员加入项目。
        </template>
      </p>

      <button
        v-if="selected"
        type="button"
        class="mobile-back"
        @click="backToQueue"
      >
        ← 待验收
      </button>

      <div class="review-workspace" :class="{ 'detail-selected': !!selected }">
        <ReviewQueue
          :items="visible"
          :selected-id="selected?.id"
          @select="select"
        />

        <ReviewSubmissionDetail
          v-if="selected"
          :round="selected"
          :history="selectedHistory"
          :can-approve="canAct"
          :can-reject="canRequestChanges"
          :can-correct="canCorrect"
          :busy="
            workspace.pendingAction === 'review' ||
            workspace.pendingAction === 'review-correction'
          "
          @preview="openPreview"
          @download="downloadAttachment"
          @approve="approve"
          @request-changes="requestChanges"
          @correct-request-changes="correctRequestChanges"
        />

        <FilePreviewPanel
          v-if="previewVersion"
          :project-id="String(route.params.projectId)"
          :file-version="asPreviewFileVersion(previewVersion)"
          :uploader-name="workspace.memberName(previewVersion.uploadedBy)"
          @close="previewVersion = null"
        />
      </div>
    </PageState>
  </div>
</template>

<style scoped>
.review-toolbar {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: center;
  margin-bottom: 14px;
}
.review-tabs {
  display: inline-flex;
  gap: var(--space-xs);
  border-bottom: 1px solid var(--tu-border);
}
.review-tabs button {
  min-height: 36px;
  border: 0;
  border-radius: 0;
  background: transparent;
  color: var(--tu-muted);
  cursor: pointer;
  padding: 0 13px;
}
.review-tabs button.active {
  box-shadow: inset 0 -2px var(--tu-action);
  color: var(--tu-ink);
  font-weight: 650;
}
.review-toolbar select {
  min-height: 40px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-surface);
  padding: 0 10px;
}
.review-workspace {
  display: grid;
  grid-template-columns: minmax(300px, 0.72fr) minmax(0, 1.8fr);
  gap: 14px;
  align-items: start;
}
.mobile-back {
  display: none;
}
@media (max-width: 760px) {
  .review-toolbar {
    align-items: stretch;
    flex-direction: column;
  }
  .review-workspace {
    grid-template-columns: 1fr;
  }
  .detail-selected :deep(.review-queue) {
    display: none;
  }
  .mobile-back {
    display: inline-flex;
    min-height: 40px;
    margin-bottom: 8px;
    border: 0;
    background: transparent;
    color: var(--tu-blue-strong);
    cursor: pointer;
    font-weight: 700;
  }
}
</style>
