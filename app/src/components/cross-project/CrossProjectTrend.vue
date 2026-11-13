<script setup lang="ts">
import { computed } from "vue";
import type { CrossProjectAnalytics } from "@/services/cross-project";

const props = defineProps<{ trends: CrossProjectAnalytics["trends"] }>();
const maxValue = computed(() =>
  Math.max(
    1,
    ...props.trends.map((item) => Math.max(item.created, item.completed)),
  ),
);
</script>

<template>
  <section aria-label="按 UTC 日期统计的创建完成趋势" class="trend">
    <h3>每日创建与完成趋势</h3>
    <p>所有项目统一使用 UTC 日期桶。蓝色：创建；深色：完成。</p>
    <div class="trend-scroll">
      <div
        v-for="day in trends"
        :key="day.day"
        class="day"
        :title="day.day + ' 创建 ' + day.created + '，完成 ' + day.completed"
      >
        <div class="bars">
          <i
            class="created"
            :style="{ height: (day.created / maxValue) * 100 + '%' }"
          />
          <i
            class="completed"
            :style="{ height: (day.completed / maxValue) * 100 + '%' }"
          />
        </div>
        <time :datetime="day.day">{{ day.day.slice(5) }}</time>
      </div>
    </div>
    <p v-if="!trends.length">当前窗口没有日期数据。</p>
  </section>
</template>

<style scoped>
.trend h3 {
  margin: 0 0 6px;
}
.trend p {
  color: var(--tu-muted);
  margin: 0 0 12px;
}
.trend-scroll {
  display: flex;
  gap: 6px;
  overflow-x: auto;
  max-width: 100%;
  padding: var(--space-lg) var(--space-xs) var(--space-sm);
  background: transparent;
  border-top: 1px solid var(--tu-border);
  border-bottom: 1px solid var(--tu-border);
}
.day {
  display: grid;
  gap: 6px;
  text-align: center;
  flex: 1 0 32px;
  min-width: 32px;
}
.bars {
  height: 110px;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  gap: 2px;
  border-bottom: 1px solid var(--tu-border);
}
.bars i {
  width: 10px;
  min-height: 1px;
  border-radius: 3px 3px 0 0;
}
.created {
  background: var(--color-chart-tertiary);
}
.completed {
  background: var(--color-accent-hover);
}
time {
  font-size: 9px;
  color: var(--tu-muted);
  transform: rotate(-45deg);
  transform-origin: center;
  white-space: nowrap;
  padding: 8px 0;
}
</style>
