<script setup lang="ts">
import { computed } from "vue";

import StatusBadge from "@/components/common/StatusBadge.vue";
import {
  isSubmissionFileType,
  normalizeRequiredSubmissionFileTypes,
  submissionFileTypeLabel,
} from "@/domain/submission-file-types";
import type {
  ReviewRoundFileRow,
  ReviewRoundRow,
  TaskFileVersion,
} from "@/types/ui";

const props = defineProps<{
  rounds: ReviewRoundRow[];
  roundFiles: ReviewRoundFileRow[];
  versions: TaskFileVersion[];
}>();

const versionById = computed(
  () =>
    new Map(
      props.versions.map(
        (version) => [version.fileVersionId, version] as const,
      ),
    ),
);

function attachments(roundId: string) {
  return props.roundFiles
    .filter((item) => item.review_round_id === roundId)
    .sort((a, b) => a.position - b.position)
    .map((item) => ({
      binding: item,
      version: versionById.value.get(item.file_version_id),
    }));
}

function requiredTypes(round: ReviewRoundRow) {
  const snapshot = normalizeRequiredSubmissionFileTypes(
    round.required_submission_file_types_snapshot,
  );
  if (snapshot.length > 0) return snapshot;
  return isSubmissionFileType(round.required_submission_file_type_snapshot)
    ? [round.required_submission_file_type_snapshot]
    : [];
}

function requirementLabel(round: ReviewRoundRow) {
  return requiredTypes(round).map(submissionFileTypeLabel).join("、");
}
</script>

<template>
  <div v-if="rounds.length" class="review-list">
    <article v-for="round in rounds" :key="round.id" class="review-row">
      <div class="review-heading">
        <strong>第 {{ round.round_number }} 轮</strong>
        <StatusBadge :status="round.decision || round.state" />
      </div>
      <p class="muted">
        {{ new Date(round.submitted_at).toLocaleString() }}
      </p>
      <p v-if="requiredTypes(round).length" class="muted">
        本轮要求：至少包含以下任一类型：{{ requirementLabel(round) }}
      </p>
      <p v-if="round.submission_text_snapshot" class="review-text">
        {{ round.submission_text_snapshot }}
      </p>
      <ul v-if="attachments(round.id).length" class="review-files">
        <li
          v-for="item in attachments(round.id)"
          :key="item.binding.file_version_id"
        >
          {{
            item.version
              ? `${item.version.originalName} · v${item.version.versionNumber}`
              : "文件版本不可用"
          }}
        </li>
      </ul>
      <p v-if="round.rejection_reason" class="review-reason">
        {{ round.rejection_reason }}
      </p>
    </article>
  </div>
  <p v-else class="muted">暂无验收记录。</p>
</template>

<style scoped>
.review-list {
  display: grid;
  gap: 12px;
}

.review-row {
  display: grid;
  gap: 6px;
  padding: 12px;
  border: 1px solid var(--van-border-color);
  border-radius: 10px;
}

.review-heading {
  display: flex;
  gap: 8px;
  align-items: center;
}

.muted,
.review-text,
.review-reason {
  margin: 0;
}

.review-text {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.review-files {
  margin: 0;
  padding-left: 20px;
}
</style>
