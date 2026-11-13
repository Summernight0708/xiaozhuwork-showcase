<script setup lang="ts">
import { ref, watch } from "vue";

import ReviewRoundHistory from "@/components/review/ReviewRoundHistory.vue";
import { displayReviewLabel } from "@/domain/presentation-labels";
import { isPreviewSupported } from "@/domain/project-files-ui";
import type {
  ReviewAttachmentSnapshot,
  ReviewRoundSnapshot,
} from "@/types/frontend-integration";

const props = withDefaults(
  defineProps<{
    round: ReviewRoundSnapshot;
    history: readonly ReviewRoundSnapshot[];
    canApprove: boolean;
    canReject: boolean;
    canCorrect?: boolean;
    busy?: boolean;
  }>(),
  {
    canCorrect: false,
    busy: false,
  },
);

const emit = defineEmits<{
  preview: [attachment: ReviewAttachmentSnapshot];
  download: [attachment: ReviewAttachmentSnapshot];
  approve: [];
  requestChanges: [reason: string];
  correctRequestChanges: [];
}>();

const reason = ref("");
const showChanges = ref(false);
const showApproveConfirm = ref(false);

watch(
  () => props.round.id,
  () => {
    reason.value = "";
    showChanges.value = false;
    showApproveConfirm.value = false;
  },
);

function submitChanges() {
  const value = reason.value.trim();
  if (!value) return;
  emit("requestChanges", value);
  showChanges.value = false;
}
</script>

<template>
  <article class="review-detail">
    <header class="detail-header">
      <div>
        <span class="muted">第 {{ round.roundNumber }} 轮验收</span>
        <h2>{{ round.taskTitle }}</h2>
        <p>
          {{ round.submitterName }} ·
          {{ new Date(round.submittedAt).toLocaleString() }}
        </p>
      </div>
      <span class="status">{{
        displayReviewLabel(round.decision, round.state)
      }}</span>
    </header>

    <section class="detail-block">
      <h3>说明</h3>
      <p v-if="round.textSnapshot" class="submission-text">
        {{ round.textSnapshot }}
      </p>
      <p v-else class="muted">本轮没有文字说明。</p>
    </section>

    <section class="detail-block">
      <h3>附件</h3>
      <div v-if="round.attachments.length" class="attachment-list">
        <div
          v-for="attachment in round.attachments"
          :key="attachment.fileVersionId"
          class="attachment-row"
        >
          <div>
            <strong>{{ attachment.originalName }}</strong>
            <small>v{{ attachment.versionNumber }}</small>
          </div>
          <div class="attachment-actions">
            <button
              v-if="
                isPreviewSupported(attachment.originalName, attachment.mimeType)
              "
              type="button"
              :aria-label="'预览 ' + attachment.originalName"
              @click="emit('preview', attachment)"
            >
              预览
            </button>
            <span v-else class="muted">该格式暂不支持在线预览</span>
            <button
              type="button"
              :aria-label="'下载 ' + attachment.originalName"
              @click="emit('download', attachment)"
            >
              下载
            </button>
          </div>
        </div>
      </div>
      <p v-else class="muted">本轮没有附件。</p>
    </section>

    <section v-if="round.requirement" class="detail-block">
      <h3>提交要求</h3>
      <p>
        {{ round.requirement.satisfied ? "✓" : "✕" }}
        至少包含以下任一类型：{{
          round.requirement.requiredFileTypes
            .map((type) => type.toUpperCase())
            .join("、")
        }}
      </p>
    </section>

    <section class="detail-block">
      <h3>历史轮次</h3>
      <ReviewRoundHistory
        :rounds="history"
        @preview="emit('preview', $event)"
        @download="emit('download', $event)"
      />
    </section>

    <section v-if="round.reviewComment" class="review-comment">
      <strong>验收意见</strong>
      <p>{{ round.reviewComment }}</p>
    </section>

    <section v-if="canCorrect" class="correction-panel">
      <div>
        <strong>误打回纠正</strong>
        <p>
          原“要求修改”记录会永久保留；纠正后，同一份提交会新增一轮待验收记录。
        </p>
      </div>
      <button
        type="button"
        class="danger-outline"
        :disabled="busy"
        @click="emit('correctRequestChanges')"
      >
        纠正误打回
      </button>
    </section>

    <footer v-if="canApprove || canReject" class="review-actions">
      <template v-if="showChanges">
        <label class="reason-field">
          <span>修改意见</span>
          <textarea v-model="reason" rows="3" maxlength="1000" />
        </label>
        <div class="action-row">
          <button type="button" @click="showChanges = false">取消</button>
          <button
            type="button"
            class="danger"
            :disabled="!reason.trim() || busy"
            @click="submitChanges"
          >
            确认要求修改
          </button>
        </div>
      </template>
      <template v-else-if="showApproveConfirm && canApprove">
        <div class="approve-confirm" role="alert">
          <strong>通过本轮提交？</strong>
          <p>
            本轮包含 {{ round.attachments.length }} 个文件
            <template v-if="round.textSnapshot"> · 1 段文字说明</template>。
          </p>
          <p>通过后，这些文件版本将成为该任务正式成果。</p>
        </div>
        <div class="action-row">
          <button type="button" @click="showApproveConfirm = false">
            取消
          </button>
          <button
            type="button"
            class="primary"
            :disabled="busy"
            @click="emit('approve')"
          >
            确认通过
          </button>
        </div>
      </template>
      <template v-else>
        <button
          v-if="canReject"
          type="button"
          class="danger-outline"
          @click="showChanges = true"
        >
          要求修改
        </button>
        <button
          v-if="canApprove"
          type="button"
          class="primary"
          @click="showApproveConfirm = true"
        >
          通过
        </button>
      </template>
    </footer>
  </article>
</template>

<style scoped>
.review-detail {
  padding: 22px;
  border: 1px solid var(--tu-border);
  border-radius: var(--tu-radius);
  background: var(--tu-surface);
}
.detail-header {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  align-items: flex-start;
}
.detail-header h2 {
  margin: 4px 0 5px;
}
.detail-header p,
.muted {
  color: var(--tu-muted);
}
.status {
  color: var(--tu-muted);
  font-size: 12px;
}
.detail-block {
  margin-top: 22px;
}
.detail-block h3 {
  margin: 0 0 10px;
  font-size: 14px;
}
.attachment-list {
  display: grid;
  gap: 9px;
}
.attachment-row {
  display: flex;
  justify-content: space-between;
  gap: 14px;
  padding: 12px;
  border: 1px solid var(--tu-border);
  border-radius: 10px;
}
.attachment-row > div:first-child {
  display: grid;
  gap: 4px;
}
.attachment-row small {
  color: var(--tu-muted);
}
.attachment-actions {
  display: flex;
  gap: 7px;
  align-items: center;
}
.attachment-actions button {
  border: 0;
  background: transparent;
  color: var(--tu-blue-strong);
  cursor: pointer;
  font-weight: 700;
}
.review-comment,
.approve-confirm,
.correction-panel {
  margin-top: 18px;
  padding: 13px;
  border-radius: 10px;
  background: var(--tu-warning-surface);
}
.review-comment p,
.approve-confirm p {
  margin: 5px 0 0;
}
.correction-panel {
  margin-top: 18px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.correction-panel p {
  margin: 5px 0 0;
  color: var(--tu-muted);
}
.correction-panel button {
  min-height: 40px;
  padding: 0 13px;
  border-radius: 9px;
  background: var(--tu-surface);
  cursor: pointer;
}
.correction-panel .danger-outline {
  color: var(--tu-danger);
  border: 1px solid #f1b4ae;
}
.review-actions {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  margin-top: 22px;
  padding-top: 16px;
  border-top: 1px solid var(--tu-border);
}
.reason-field {
  width: 100%;
  display: grid;
  gap: 6px;
}
.reason-field textarea {
  width: 100%;
  resize: vertical;
}
.action-row {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
.review-actions button {
  min-height: 44px;
  padding: 0 13px;
  border: 1px solid var(--tu-action-border);
  border-radius: 9px;
  background: var(--tu-action-surface);
  color: var(--tu-action);
  cursor: pointer;
}
.review-actions .primary {
  border-color: var(--tu-action);
  background: var(--tu-action);
  color: var(--tu-action-contrast);
  font-weight: 700;
}
@media (hover: hover) {
  .review-actions button:not(:disabled):hover {
    background: var(--tu-action-surface-hover);
  }
  .review-actions .primary:not(:disabled):hover {
    border-color: var(--tu-action-hover);
    background: var(--tu-action-hover);
  }
}
.review-actions button:not(:disabled):active {
  background: var(--tu-action-surface-active);
}
.review-actions .primary:not(:disabled):active {
  border-color: var(--tu-action-active);
  background: var(--tu-action-active);
}
.review-actions .danger,
.review-actions .danger-outline {
  color: var(--tu-danger);
  border-color: #f1b4ae;
}
@media (max-width: 720px) {
  .review-detail {
    padding: 16px;
    border: 0;
    border-radius: 0;
  }
  .attachment-row,
  .detail-header {
    display: grid;
  }
  .attachment-actions {
    flex-wrap: wrap;
  }
  .review-actions {
    display: grid;
  }
}
</style>
