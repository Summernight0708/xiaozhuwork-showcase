<script setup lang="ts">
import { computed } from "vue";
import type { ProjectAnalytics } from "@/services/project-analytics";

const props = defineProps<{
  members: ProjectAnalytics["memberTaskDistribution"];
  difficulty: ProjectAnalytics["difficultyDistribution"];
}>();

const memberPeak = computed(() =>
  Math.max(1, ...props.members.map((item) => item.count)),
);
const difficultyPeak = computed(() =>
  Math.max(1, ...props.difficulty.map((item) => item.count)),
);

function memberLabel(item: ProjectAnalytics["memberTaskDistribution"][number]) {
  if (item.kind === "former_member") return "已离开成员";
  if (item.kind === "unassigned") return "未分配";
  return `成员 ${item.userId?.slice(0, 8)}`;
}

function starLabel(stars: number | null) {
  return stars === null ? "未评级" : `${stars} 星`;
}
</script>

<template>
  <div class="distribution-grid">
    <section class="analytics-panel" aria-labelledby="member-tasks-title">
      <header>
        <h2 id="member-tasks-title">主负责人任务</h2>
        <p>只按任务当前主负责人计数，不重复计算协作者。</p>
      </header>
      <div v-if="members.length" class="bar-list">
        <div v-for="item in members" :key="`${item.kind}:${item.userId}`">
          <div class="bar-label">
            <span>{{ memberLabel(item) }}</span>
            <strong>{{ item.count }}</strong>
          </div>
          <div class="track">
            <i :style="{ width: `${(item.count / memberPeak) * 100}%` }" />
          </div>
        </div>
      </div>
      <p v-else class="panel-zero">当前项目没有未取消任务。</p>
    </section>

    <section class="analytics-panel" aria-labelledby="difficulty-title">
      <header>
        <h2 id="difficulty-title">任务难度</h2>
        <p>按任务当前 1–5 星权重与未评级分桶。</p>
      </header>
      <div class="bar-list difficulty-list">
        <div v-for="item in difficulty" :key="String(item.stars)">
          <div class="bar-label">
            <span>{{ starLabel(item.stars) }}</span>
            <strong>{{ item.count }}</strong>
          </div>
          <div class="track">
            <i :style="{ width: `${(item.count / difficultyPeak) * 100}%` }" />
          </div>
        </div>
      </div>
    </section>
  </div>
</template>

<style scoped>
.distribution-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
}

.analytics-panel {
  min-width: 0;
  padding: 18px;
  border: 1px solid var(--tu-border);
  border-radius: 14px;
  background: var(--tu-surface);
}

h2,
p {
  margin: 0;
}

h2 {
  color: var(--tu-ink);
  font-size: 17px;
}

header p,
.panel-zero {
  margin-top: 5px;
  color: var(--tu-muted);
  font-size: 12px;
  line-height: 1.5;
}

.bar-list {
  display: grid;
  gap: 13px;
  margin-top: 18px;
}

.bar-label {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  color: var(--tu-muted);
  font-size: 12px;
}

.bar-label span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.bar-label strong {
  color: var(--tu-ink);
  font-variant-numeric: tabular-nums;
}

.track {
  height: 7px;
  margin-top: 6px;
  overflow: hidden;
  border-radius: 999px;
  background: var(--tu-quiet-surface);
}

.track i {
  display: block;
  min-width: 0;
  height: 100%;
  border-radius: inherit;
  background: var(--color-chart-tertiary);
}

.difficulty-list .track i {
  background: #b2865d;
}

@media (max-width: 780px) {
  .distribution-grid {
    grid-template-columns: 1fr;
  }
}
</style>
