<script setup lang="ts">
import type { ProjectAnalyticsTotals } from "@/services/project-analytics";

defineProps<{ totals: ProjectAnalyticsTotals }>();

const cards: Array<{
  key: keyof ProjectAnalyticsTotals;
  label: string;
  tone: string;
}> = [
  { key: "taskTotal", label: "任务总数", tone: "neutral" },
  { key: "completedTasks", label: "当前已完成", tone: "positive" },
  { key: "overdueTasks", label: "当前逾期", tone: "warning" },
  { key: "awaitingReviewTasks", label: "等待验收", tone: "accent" },
  { key: "blockedTasks", label: "当前受阻", tone: "danger" },
  { key: "completedInWindow", label: "窗口内完成", tone: "positive" },
];
</script>

<template>
  <section class="analytics-summary" aria-label="项目分析摘要">
    <article
      v-for="card in cards"
      :key="card.key"
      data-test="analytics-summary-card"
      :data-tone="card.tone"
    >
      <span>{{ card.label }}</span>
      <strong>{{ totals[card.key].toLocaleString() }}</strong>
    </article>
  </section>
</template>

<style scoped>
.analytics-summary {
  display: grid;
  grid-template-columns: repeat(6, minmax(112px, 1fr));
  gap: 10px;
}

.analytics-summary article {
  min-width: 0;
  padding: 16px;
  border: 1px solid var(--tu-border);
  border-radius: 14px;
  background: var(--tu-surface);
}

.analytics-summary span,
.analytics-summary strong {
  display: block;
}

.analytics-summary span {
  color: var(--tu-muted);
  font-size: 12px;
}

.analytics-summary strong {
  margin-top: 8px;
  color: var(--tu-ink);
  font-size: clamp(22px, 3vw, 30px);
  font-variant-numeric: tabular-nums;
}

.analytics-summary article[data-tone="positive"] strong {
  color: var(--tu-success);
}

.analytics-summary article[data-tone="warning"] strong,
.analytics-summary article[data-tone="danger"] strong {
  color: var(--tu-warning);
}

.analytics-summary article[data-tone="accent"] strong {
  color: var(--tu-blue-strong);
}

@media (max-width: 1100px) {
  .analytics-summary {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}

@media (max-width: 560px) {
  .analytics-summary {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
</style>
