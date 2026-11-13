<script setup lang="ts">
import { displayReviewLabel } from "@/domain/presentation-labels";
import type { ReviewRoundSnapshot } from "@/types/frontend-integration";

defineProps<{
  items: readonly ReviewRoundSnapshot[];
  selectedId?: string | null;
}>();

const emit = defineEmits<{
  select: [round: ReviewRoundSnapshot];
}>();
</script>

<template>
  <aside class="review-queue review-list" aria-label="提交队列">
    <button
      v-for="round in items"
      :key="round.id"
      type="button"
      class="queue-item"
      :class="{ selected: selectedId === round.id }"
      :aria-current="selectedId === round.id ? 'true' : undefined"
      @click="emit('select', round)"
    >
      <span class="queue-main">
        <strong>{{ round.taskTitle }}</strong>
        <small>{{ round.submitterName }} · 第{{ round.roundNumber }}轮</small>
        <small>{{ new Date(round.submittedAt).toLocaleString() }}</small>
      </span>
      <span class="queue-status">{{
        displayReviewLabel(round.decision, round.state)
      }}</span>
    </button>
  </aside>
</template>

<style scoped>
.review-queue {
  overflow: hidden;
  border-top: 1px solid var(--tu-border);
  background: transparent;
}
.queue-item {
  width: 100%;
  min-height: 78px;
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: center;
  padding: 13px 14px;
  border: 0;
  border-bottom: 1px solid var(--tu-border);
  background: var(--tu-surface);
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.queue-item:last-child {
  border-bottom: 0;
}
.queue-item.selected {
  background: var(--tu-blue-soft);
}
.queue-main {
  display: grid;
  gap: 3px;
}
.queue-main small {
  color: var(--tu-muted);
}
.queue-status {
  color: var(--tu-muted);
  font-size: 12px;
  white-space: nowrap;
}
</style>
