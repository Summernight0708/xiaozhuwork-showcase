<script setup lang="ts">
defineOptions({ name: "ProjectAnalyticsView" });

import { computed, onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import AnalyticsDistributionPanels from "@/components/analytics/AnalyticsDistributionPanels.vue";
import AnalyticsProvenanceNotice from "@/components/analytics/AnalyticsProvenanceNotice.vue";
import AnalyticsSummaryCards from "@/components/analytics/AnalyticsSummaryCards.vue";
import AnalyticsTimingCycle from "@/components/analytics/AnalyticsTimingCycle.vue";
import AnalyticsTrendsChart from "@/components/analytics/AnalyticsTrendsChart.vue";
import { getBackend } from "@/services/backend";
import {
  ProjectAnalyticsServiceError,
  createDefaultAnalyticsWindow,
  createProjectAnalyticsService,
  projectAnalyticsFailurePresentation,
  type ProjectAnalytics,
  type ProjectAnalyticsFailureCode,
} from "@/services/project-analytics";

const props = defineProps<{ projectId?: string }>();
const route = useRoute();
const routeProjectId = computed(() => {
  const value = props.projectId ?? route.params.projectId;
  return Array.isArray(value) ? (value[0] ?? "") : String(value ?? "");
});

const initialWindow = createDefaultAnalyticsWindow();
const fromInput = ref(initialWindow.from.slice(0, 16));
const toInput = ref(initialWindow.to.slice(0, 16));
const loading = ref(false);
const analytics = ref<ProjectAnalytics | null>(null);
const failureCode = ref<ProjectAnalyticsFailureCode | null>(null);

const failure = computed(() =>
  failureCode.value
    ? projectAnalyticsFailurePresentation(failureCode.value)
    : null,
);
const asOfLabel = computed(() =>
  analytics.value
    ? new Intl.DateTimeFormat("zh-CN", {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: "UTC",
      }).format(new Date(analytics.value.asOf))
    : "",
);

function utcInstant(value: string) {
  return `${value}:00.000Z`;
}

async function loadAnalytics() {
  loading.value = true;
  failureCode.value = null;
  try {
    const backend = getBackend();
    if (!backend) {
      failureCode.value = "SERVICE_UNAVAILABLE";
      return;
    }
    const service = createProjectAnalyticsService({
      async rpc(name, args) {
        const response = await backend.client.rpc(name as never, args as never);
        return response as { data: unknown; error: unknown };
      },
    });
    const result = await service.getProjectAnalytics({
      projectId: routeProjectId.value,
      from: utcInstant(fromInput.value),
      to: utcInstant(toInput.value),
    });
    if (!result.ok) {
      analytics.value = null;
      failureCode.value = result.code;
      return;
    }
    analytics.value = result;
  } catch (error) {
    analytics.value = null;
    failureCode.value =
      error instanceof ProjectAnalyticsServiceError
        ? error.code
        : "SERVICE_UNAVAILABLE";
  } finally {
    loading.value = false;
  }
}

onMounted(loadAnalytics);
</script>

<template>
  <main class="xiaozhuwork-page analytics-page">
    <header class="analytics-head">
      <div>
        <span class="eyebrow">Pro · 项目分析</span>
        <h1>项目运行数据</h1>
      </div>
      <form
        class="range-form"
        aria-label="UTC 时间范围"
        @submit.prevent="loadAnalytics"
      >
        <label>
          <span>开始（UTC）</span>
          <input v-model="fromInput" type="datetime-local" required />
        </label>
        <label>
          <span>结束（UTC）</span>
          <input v-model="toInput" type="datetime-local" required />
        </label>
        <button type="submit" :disabled="loading">
          {{ loading ? "加载中…" : "应用范围" }}
        </button>
      </form>
    </header>

    <section v-if="loading && !analytics" class="state-card" aria-live="polite">
      <strong>正在加载项目分析…</strong>
      <p>正在校验当前成员身份、发布状态和项目权益。</p>
    </section>

    <section
      v-else-if="failure"
      class="state-card state-card--failure"
      role="status"
    >
      <strong>{{ failure.title }}</strong>
      <p>{{ failure.detail }}</p>
      <button
        v-if="failureCode === 'SERVICE_UNAVAILABLE'"
        type="button"
        @click="loadAnalytics"
      >
        重试
      </button>
    </section>

    <template v-else-if="analytics">
      <div class="analytics-status">
        <span>截至 {{ asOfLabel }} UTC</span>
        <span
          >窗口 {{ analytics.window.from }} — {{ analytics.window.to }}</span
        >
      </div>

      <AnalyticsSummaryCards :totals="analytics.totals" />

      <section
        v-if="analytics.totals.taskTotal === 0"
        class="state-card zero-card"
      >
        <strong>当前没有未取消任务</strong>
        <p>趋势仍展示所选 UTC 日期范围；难度分布保持六个零值分桶。</p>
      </section>

      <AnalyticsTrendsChart :trends="analytics.trends" />
      <AnalyticsDistributionPanels
        :members="analytics.memberTaskDistribution"
        :difficulty="analytics.difficultyDistribution"
      />
      <AnalyticsTimingCycle
        :timing="analytics.completionTiming"
        :cycle="analytics.projectCycle"
      />
      <AnalyticsProvenanceNotice :analytics="analytics" />
    </template>
  </main>
</template>

<style scoped>
.analytics-page {
  width: 100%;

  display: grid;
  gap: 14px;
}

.analytics-head {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 24px;
  padding: 4px 0 8px;
}

.eyebrow {
  color: var(--tu-muted);
  font-size: 12px;
  font-weight: 800;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

h1,
p {
  margin: 0;
}

h1 {
  margin-top: 5px;
  color: var(--tu-ink);
  font-size: clamp(28px, 3vw, 40px);
  letter-spacing: -0.04em;
}

.analytics-head > div > p {
  margin-top: 5px;
  color: var(--tu-muted);
  font-size: 13px;
}

.range-form {
  display: flex;
  align-items: end;
  gap: 8px;
  padding: 10px;
  border: 1px solid var(--tu-border);
  border-radius: 12px;
  background: var(--tu-surface);
}

.range-form label {
  display: grid;
  gap: 5px;
}

.range-form label span {
  color: var(--tu-muted);
  font-size: 10px;
  font-weight: 700;
}

.range-form input {
  min-height: 36px;
  padding: 0 9px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-bg);
  color: var(--tu-ink);
  font: inherit;
  font-size: 12px;
}

.range-form button,
.state-card button {
  min-height: 36px;
  padding: 0 14px;
  border: 0;
  border-radius: 8px;
  background: #536b7d;
  color: white;
  font: inherit;
  font-size: 12px;
  font-weight: 700;
  cursor: pointer;
}

.range-form button:disabled {
  cursor: wait;
  opacity: 0.65;
}

.analytics-status {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 8px;
  color: var(--tu-muted);
  font-size: 11px;
  font-variant-numeric: tabular-nums;
}

.state-card {
  padding: 26px;
  border: 1px solid var(--tu-border);
  border-radius: 14px;
  background: var(--tu-surface);
  text-align: center;
}

.state-card strong {
  color: var(--tu-ink);
  font-size: 16px;
}

.state-card p {
  margin-top: 6px;
  color: var(--tu-muted);
  font-size: 13px;
}

.state-card button {
  margin-top: 14px;
}

.state-card--failure {
  border-color: var(--tu-border);
  background: var(--tu-warning-surface);
}

.zero-card {
  padding: 18px;
}

@media (max-width: 980px) {
  .analytics-head {
    align-items: stretch;
    flex-direction: column;
  }

  .range-form {
    width: 100%;
  }

  .range-form label {
    flex: 1;
  }
}

@media (max-width: 640px) {
  .range-form {
    align-items: stretch;
    flex-direction: column;
  }

  .range-form button {
    margin-top: 3px;
  }

  .analytics-status {
    display: grid;
  }
}
</style>
