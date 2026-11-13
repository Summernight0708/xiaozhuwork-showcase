<script setup lang="ts">
import { computed } from "vue";
import type { ProjectAnalytics } from "@/services/project-analytics";

const props = defineProps<{ trends: ProjectAnalytics["trends"] }>();

const width = 720;
const height = 228;
const insetX = 28;
const insetY = 22;
const plotWidth = width - insetX * 2;
const plotHeight = height - insetY * 2;

const peak = computed(() =>
  Math.max(
    1,
    ...props.trends.flatMap((item) => [item.created, item.completed]),
  ),
);
const hasEvents = computed(() =>
  props.trends.some((item) => item.created > 0 || item.completed > 0),
);

function x(index: number) {
  if (props.trends.length <= 1) return width / 2;
  return insetX + (index / (props.trends.length - 1)) * plotWidth;
}

function y(value: number) {
  return insetY + plotHeight - (value / peak.value) * plotHeight;
}

function points(key: "created" | "completed") {
  return props.trends
    .map((item, index) => `${x(index)},${y(item[key])}`)
    .join(" ");
}

const firstDay = computed(() => props.trends[0]?.day ?? "—");
const lastDay = computed(
  () => props.trends[props.trends.length - 1]?.day ?? "—",
);
</script>

<template>
  <section class="analytics-panel trend-panel" aria-labelledby="trend-title">
    <header>
      <div>
        <h2 id="trend-title">创建与完成趋势</h2>
        <p>按 UTC 日历日统计当前保留、未取消的任务。</p>
      </div>
      <div class="legend" aria-label="图例">
        <span><i class="created" />创建</span>
        <span><i class="completed" />完成</span>
      </div>
    </header>

    <div v-if="trends.length" class="chart-wrap">
      <svg
        :viewBox="`0 0 ${width} ${height}`"
        role="img"
        aria-labelledby="trend-title trend-description"
      >
        <desc id="trend-description">
          项目任务按 UTC 日期的创建数与完成数折线图
        </desc>
        <line
          :x1="insetX"
          :x2="width - insetX"
          :y1="height - insetY"
          :y2="height - insetY"
          class="axis"
        />
        <polyline
          :points="points('created')"
          class="line-created"
          fill="none"
        />
        <polyline
          :points="points('completed')"
          class="line-completed"
          fill="none"
        />
        <g v-for="(item, index) in trends" :key="item.day">
          <circle
            :cx="x(index)"
            :cy="y(item.created)"
            r="3.5"
            class="dot-created"
          >
            <title>{{ item.day }} 创建 {{ item.created }}</title>
          </circle>
          <circle
            :cx="x(index)"
            :cy="y(item.completed)"
            r="3.5"
            class="dot-completed"
          >
            <title>{{ item.day }} 完成 {{ item.completed }}</title>
          </circle>
        </g>
      </svg>
      <div class="axis-labels">
        <span>{{ firstDay }}</span>
        <span>UTC</span>
        <span>{{ lastDay }}</span>
      </div>
      <p v-if="!hasEvents" class="chart-zero">
        这个时间范围内没有创建或完成记录。
      </p>
    </div>
    <p v-else class="panel-zero">所选时间范围内没有可显示的日期。</p>
  </section>
</template>

<style scoped>
.analytics-panel {
  min-width: 0;
  padding: 18px;
  border: 1px solid var(--tu-border);
  border-radius: 14px;
  background: var(--tu-surface);
}

header {
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: 16px;
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
.panel-zero,
.chart-zero {
  margin-top: 5px;
  color: var(--tu-muted);
  font-size: 12px;
}

.legend {
  display: flex;
  gap: 12px;
  color: var(--tu-muted);
  font-size: 11px;
}

.legend span {
  display: inline-flex;
  align-items: center;
  gap: 5px;
}

.legend i {
  width: 16px;
  height: 3px;
  border-radius: 2px;
}

.legend .created,
.line-created,
.dot-created {
  color: var(--color-chart-tertiary);
  background: var(--color-chart-tertiary);
  stroke: var(--color-chart-tertiary);
  fill: var(--color-chart-tertiary);
}

.legend .completed,
.line-completed,
.dot-completed {
  color: var(--color-chart-primary);
  background: var(--color-chart-primary);
  stroke: var(--color-chart-primary);
  fill: var(--color-chart-primary);
}

.chart-wrap {
  position: relative;
  margin-top: 14px;
}

svg {
  display: block;
  width: 100%;
  height: auto;
}

.axis {
  stroke: var(--tu-border);
}

.line-created,
.line-completed {
  stroke-width: 3;
  stroke-linecap: round;
  stroke-linejoin: round;
}

.axis-labels {
  display: flex;
  justify-content: space-between;
  color: var(--tu-muted);
  font-size: 10px;
  font-variant-numeric: tabular-nums;
}

.chart-zero {
  text-align: center;
}

@media (max-width: 600px) {
  header {
    flex-direction: column;
  }
}
</style>
