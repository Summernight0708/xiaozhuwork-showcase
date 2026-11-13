<script setup lang="ts">
import type { ProjectAnalytics } from "@/services/project-analytics";

defineProps<{
  timing: ProjectAnalytics["completionTiming"];
  cycle: ProjectAnalytics["projectCycle"];
}>();

function formatDuration(seconds: number | null) {
  if (seconds === null) return "暂无样本";
  const days = Math.floor(seconds / 86_400);
  const hours = Math.floor((seconds % 86_400) / 3_600);
  const minutes = Math.floor((seconds % 3_600) / 60);
  if (days > 0) return `${days} 天 ${hours} 小时`;
  if (hours > 0) return `${hours} 小时 ${minutes} 分钟`;
  return `${minutes} 分钟`;
}

function formatDate(value: string | null) {
  if (!value) return "进行中";
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    timeZone: "UTC",
  }).format(new Date(value));
}
</script>

<template>
  <div class="timing-grid">
    <section class="analytics-panel" aria-labelledby="completion-timing-title">
      <header>
        <h2 id="completion-timing-title">完成用时</h2>
        <p>窗口内完成任务从创建到完成的墙钟时间，不代表劳动工时。</p>
      </header>
      <dl>
        <div>
          <dt>有效样本</dt>
          <dd>{{ timing.count }}</dd>
        </div>
        <div>
          <dt>平均</dt>
          <dd>{{ formatDuration(timing.averageSeconds) }}</dd>
        </div>
        <div>
          <dt>中位数</dt>
          <dd>{{ formatDuration(timing.medianSeconds) }}</dd>
        </div>
        <div>
          <dt>异常时间行</dt>
          <dd>{{ timing.invalidTimeRows }}</dd>
        </div>
      </dl>
    </section>

    <section class="analytics-panel" aria-labelledby="project-cycle-title">
      <header>
        <h2 id="project-cycle-title">项目周期</h2>
        <p>
          起点来自{{
            cycle.startSource === "start_at" ? "项目开始时间" : "项目创建时间"
          }}。
        </p>
      </header>
      <dl>
        <div>
          <dt>开始</dt>
          <dd>{{ formatDate(cycle.startAt) }}</dd>
        </div>
        <div>
          <dt>截止</dt>
          <dd>{{ formatDate(cycle.deadlineAt) }}</dd>
        </div>
        <div>
          <dt>{{ cycle.completedAt ? "完成" : "当前已历时" }}</dt>
          <dd>
            {{
              formatDuration(
                cycle.completedCycleSeconds ?? cycle.elapsedSeconds,
              )
            }}
          </dd>
        </div>
        <div>
          <dt>完成日期</dt>
          <dd>{{ formatDate(cycle.completedAt) }}</dd>
        </div>
      </dl>
    </section>
  </div>
</template>

<style scoped>
.timing-grid {
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
p,
dl,
dd {
  margin: 0;
}

h2 {
  color: var(--tu-ink);
  font-size: 17px;
}

header p {
  margin-top: 5px;
  color: var(--tu-muted);
  font-size: 12px;
  line-height: 1.5;
}

dl {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
  margin-top: 16px;
}

dl div {
  padding: 12px;
  border-radius: 10px;
  background: var(--tu-subtle-surface);
}

dt {
  color: var(--tu-muted);
  font-size: 11px;
}

dd {
  margin-top: 5px;
  color: var(--tu-ink);
  font-size: 14px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}

@media (max-width: 780px) {
  .timing-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 420px) {
  dl {
    grid-template-columns: 1fr;
  }
}
</style>
