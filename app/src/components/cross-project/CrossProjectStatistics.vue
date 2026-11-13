<script setup lang="ts">
import { computed } from "vue";
import type { CrossProjectAnalytics } from "@/services/cross-project";

const props = defineProps<{ data: CrossProjectAnalytics }>();
const metrics = computed(() => [
  ["任务总数", props.data.totals.taskTotal],
  ["已完成", props.data.totals.completedTasks],
  ["逾期", props.data.totals.overdueTasks],
  ["待验收", props.data.totals.awaitingReviewTasks],
  ["阻塞", props.data.totals.blockedTasks],
  ["窗口内完成", props.data.totals.completedInWindow],
]);
const rate = computed(() =>
  props.data.completionRate === null
    ? "暂无任务"
    : (props.data.completionRate * 100).toFixed(1) + "%",
);
</script>

<template>
  <section class="analytics-results" aria-label="跨项目汇总统计">
    <div class="header">
      <h2>汇总统计</h2>
      <span>{{ data.projectCount }} 个项目 · {{ rate }} 完成率</span>
    </div>
    <p v-if="!data.historyComplete" class="caveat" role="note">
      历史数据不完整：仅统计当前保留任务的创建/完成时间，不代表历史状态快照。
    </p>
    <div class="metric-grid">
      <article v-for="[label, value] in metrics" :key="label" class="metric">
        <p>{{ label }}</p>
        <strong>{{ value }}</strong>
      </article>
    </div>
    <h3>任务难度（非贡献积分）</h3>
    <div
      v-for="bucket in data.difficultyDistribution"
      :key="bucket.stars ?? 'unrated'"
      class="difficulty"
    >
      <span>{{ bucket.stars === null ? "未评级" : bucket.stars + " 星" }}</span>
      <div class="meter" :aria-label="'数量 ' + bucket.count">
        <i
          :style="{
            width: data.totals.taskTotal
              ? (bucket.count / data.totals.taskTotal) * 100 + '%'
              : '0%',
          }"
        />
      </div>
      <b>{{ bucket.count }}</b>
    </div>
    <h3>各项目摘要</h3>
    <div v-if="!data.projects.length" class="muted">当前范围没有项目。</div>
    <div
      v-for="project in data.projects"
      :key="project.projectId"
      class="summary"
    >
      <RouterLink
        :to="{
          name: 'project-overview',
          params: { projectId: project.projectId },
        }"
        >{{ project.projectId }}</RouterLink
      >
      <span
        >任务 {{ project.taskTotal }} · 完成 {{ project.completedTasks }} · 逾期
        {{ project.overdueTasks }} · 阻塞 {{ project.blockedTasks }} · 待验收
        {{ project.awaitingReviewTasks }}</span
      >
    </div>
  </section>
</template>

<style scoped>
.analytics-results {
  display: grid;
  gap: 14px;
}
.header {
  display: flex;
  gap: 10px;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
}
.header h2,
h3 {
  margin: 0;
}
.header span,
.muted {
  color: var(--tu-muted);
}
.caveat {
  margin: 0;
  color: var(--tu-warning-ink);
  border-left: 2px solid var(--tu-border);
  padding: var(--space-sm) var(--space-md);
}
.metric-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: var(--space-md);
}
.metric {
  min-width: 0;
  border-left: 1px solid var(--tu-border);
  padding: var(--space-sm) var(--space-md);
}
.metric p {
  margin: 0 0 8px;
  color: var(--tu-muted);
}
.metric strong {
  font-size: 26px;
}
.difficulty {
  display: grid;
  grid-template-columns: 65px 1fr 30px;
  gap: 10px;
  align-items: center;
}
.meter {
  background: var(--tu-quiet-surface);
  height: 12px;
  border-radius: 10px;
  overflow: hidden;
}
.meter i {
  display: block;
  height: 100%;
  background: var(--color-chart-primary);
  border-radius: 10px;
}
.summary {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  padding: var(--space-sm) 0;
  border-bottom: 1px solid var(--tu-border);
  overflow-wrap: anywhere;
}
.summary a {
  color: var(--tu-action);
}
@media (max-width: 660px) {
  .metric-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .metric strong {
    font-size: 22px;
  }
}
</style>
