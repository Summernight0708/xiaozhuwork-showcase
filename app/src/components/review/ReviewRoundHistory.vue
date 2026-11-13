<script setup lang="ts">
import { ref } from "vue";

import { displayReviewLabel } from "@/domain/presentation-labels";
import { isPreviewSupported } from "@/domain/project-files-ui";
import type {
  ReviewAttachmentSnapshot,
  ReviewRoundSnapshot,
} from "@/types/frontend-integration";

defineProps<{
  rounds: readonly ReviewRoundSnapshot[];
}>();

const emit = defineEmits<{
  preview: [attachment: ReviewAttachmentSnapshot];
  download: [attachment: ReviewAttachmentSnapshot];
}>();

const expanded = ref<string | null>(null);
</script>

<template>
  <div class="round-history">
    <button
      v-for="round in rounds"
      :key="round.id"
      type="button"
      class="history-toggle"
      :aria-expanded="expanded === round.id"
      @click="expanded = expanded === round.id ? null : round.id"
    >
      <span
        >第 {{ round.roundNumber }} 轮 ·
        {{ displayReviewLabel(round.decision, round.state) }}
        <template v-if="round.correctionOfReviewRoundId">
          · 纠错重开</template
        ></span
      >
      <span>{{ expanded === round.id ? "收起" : "查看" }}</span>
    </button>
    <template v-for="round in rounds" :key="'detail-' + round.id">
      <section v-if="expanded === round.id" class="history-detail">
        <p v-if="round.textSnapshot" class="snapshot-text">
          {{ round.textSnapshot }}
        </p>
        <p v-else class="muted">本轮没有文字说明快照。</p>
        <div
          v-for="attachment in round.attachments"
          :key="attachment.fileVersionId"
          class="history-file"
        >
          <span
            >v{{ attachment.versionNumber }} ·
            {{ attachment.originalName }}</span
          >
          <div>
            <button
              v-if="
                isPreviewSupported(attachment.originalName, attachment.mimeType)
              "
              type="button"
              @click="emit('preview', attachment)"
            >
              预览
            </button>
            <button type="button" @click="emit('download', attachment)">
              下载
            </button>
          </div>
        </div>
        <p v-if="round.reviewComment" class="review-comment">
          验收意见：{{ round.reviewComment }}
        </p>
      </section>
    </template>
  </div>
</template>

<style scoped>
.round-history {
  display: grid;
  gap: 8px;
}
.history-toggle {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 11px 12px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  cursor: pointer;
  text-align: left;
}
.history-detail {
  margin-top: -3px;
  padding: 12px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-subtle-surface);
}
.history-file {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 0;
}
.history-file button {
  border: 0;
  background: transparent;
  color: var(--tu-blue-strong);
  cursor: pointer;
  font-weight: 700;
}
.muted {
  color: var(--tu-muted);
}
.review-comment {
  margin-bottom: 0;
}
</style>
