<script setup lang="ts">
import { displayReviewLabel } from "@/domain/presentation-labels";
import {
  isSubmissionFileType,
  normalizeRequiredSubmissionFileTypes,
} from "@/domain/submission-file-types";
import type { ReviewRoundRow, TaskChangeProposalRow } from "@/types/ui";

withDefaults(
  defineProps<{
    reviews?: readonly ReviewRoundRow[];
    changeProposal?: TaskChangeProposalRow | null;
    canDecideChange?: boolean;
  }>(),
  {
    reviews: () => [],
    changeProposal: null,
    canDecideChange: false,
  },
);

function proposalRequiredTypes(
  types: readonly string[] | null | undefined,
  scalar: string | null,
) {
  const normalized = normalizeRequiredSubmissionFileTypes(types);
  if (normalized.length > 0) return normalized;
  return isSubmissionFileType(scalar) ? [scalar] : [];
}

function hasRequirementChange(proposal: TaskChangeProposalRow) {
  return (
    proposalRequiredTypes(
      proposal.old_required_submission_file_types,
      proposal.old_required_submission_file_type,
    ).join(",") !==
    proposalRequiredTypes(
      proposal.new_required_submission_file_types,
      proposal.new_required_submission_file_type,
    ).join(",")
  );
}

function requirementChangeLabel(proposal: TaskChangeProposalRow) {
  const oldTypes = proposalRequiredTypes(
    proposal.old_required_submission_file_types,
    proposal.old_required_submission_file_type,
  );
  const newTypes = proposalRequiredTypes(
    proposal.new_required_submission_file_types,
    proposal.new_required_submission_file_type,
  );
  const format = (types: readonly string[]) =>
    types.map((type) => type.toUpperCase()).join("、") || "不限制";
  return `提交要求：旧 ${format(oldTypes)} → 新 ${format(newTypes)}`;
}
</script>

<template>
  <div class="history">
    <article v-if="changeProposal" class="history-item">
      <strong>
        {{ changeProposal.state === "pending" ? "待确认变更" : "任务变更确认" }}
      </strong>
      <span>
        {{
          changeProposal.state === "pending"
            ? "等待负责人确认"
            : changeProposal.state === "approved"
              ? "已通过"
              : "已拒绝"
        }}
      </span>
      <div class="change-facts">
        <span>
          截止时间：旧
          {{ new Date(changeProposal.old_deadline_at).toLocaleString() }}
          → 新 {{ new Date(changeProposal.new_deadline_at).toLocaleString() }}
        </span>
        <span
          v-if="
            changeProposal.old_weight !== null ||
            changeProposal.new_weight !== null
          "
        >
          难度：旧 {{ changeProposal.old_weight ?? "—" }} 星 → 新
          {{ changeProposal.new_weight ?? "—" }} 星
        </span>
        <span v-if="hasRequirementChange(changeProposal)">
          {{ requirementChangeLabel(changeProposal) }}
        </span>
        <span>
          提出者：
          {{
            changeProposal.proposer_name_snapshot ||
            changeProposal.proposed_by ||
            "—"
          }}
        </span>
      </div>
      <small>{{ new Date(changeProposal.created_at).toLocaleString() }}</small>
      <slot name="change-actions" />
      <p
        v-if="changeProposal.state === 'pending' && !canDecideChange"
        class="muted"
      >
        只有当前任务负责人可以批准或拒绝；其他成员仅可查看。
      </p>
    </article>

    <details v-if="reviews.length" class="review-history">
      <summary>历史提交 · {{ reviews.length }} 轮</summary>
      <article
        v-for="round in [...reviews].sort(
          (a, b) => b.round_number - a.round_number,
        )"
        :key="round.id"
        class="history-item"
      >
        <strong>第 {{ round.round_number }} 轮</strong>
        <span>{{ displayReviewLabel(round.decision, round.state) }}</span>
        <small>{{ new Date(round.submitted_at).toLocaleString() }}</small>
        <p v-if="round.rejection_reason">{{ round.rejection_reason }}</p>
      </article>
    </details>

    <p v-if="!changeProposal && !reviews.length" class="muted">
      暂无重要历史与变更记录。
    </p>
    <slot />
  </div>
</template>

<style scoped>
.history {
  display: grid;
  gap: 10px;
  padding-top: 16px;
}
.history-item {
  display: grid;
  gap: 4px;
  padding: var(--space-md) 0;
  border-bottom: 1px solid var(--tu-border);
  background: transparent;
}
.history-item small,
.muted,
.change-facts {
  color: var(--tu-muted);
}
.history-item p {
  margin: 4px 0 0;
}
.change-facts {
  display: grid;
  gap: 4px;
  font-size: 13px;
}
.review-history summary {
  cursor: pointer;
  font-weight: 700;
}
.review-history[open] summary {
  margin-bottom: 8px;
}
</style>
