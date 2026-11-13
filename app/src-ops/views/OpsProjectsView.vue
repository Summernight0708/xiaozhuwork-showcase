<script setup lang="ts">
import { computed, onMounted, ref } from "vue";

import ActivationFunnel from "@ops/features/analytics/ActivationFunnel.vue";
import ProjectLifecycleSummary from "@ops/features/analytics/ProjectLifecycleSummary.vue";
import type {
  ProductAnalyticsOverviewV1,
  ProductAnalyticsSeriesPointV1,
} from "@ops/features/analytics/contracts";
import {
  loadProductOverview,
  loadProductTimeseries,
} from "@ops/features/analytics/api";
import { useOpsAuthStore } from "@ops/stores/auth";

const auth = useOpsAuthStore();
const loading = ref(true);
const errorCode = ref<string | null>(null);
const overview = ref<ProductAnalyticsOverviewV1 | null>(null);
const series = ref<ProductAnalyticsSeriesPointV1[]>([]);

const latestSeriesDate = computed(() => {
  const last = series.value[series.value.length - 1];
  return last?.date ?? null;
});

async function loadProjectAnalytics() {
  loading.value = true;
  errorCode.value = null;

  const token = auth.session?.access_token;
  if (!token) {
    errorCode.value = "UNAUTHENTICATED";
    loading.value = false;
    return;
  }

  const [overviewResult, seriesResult] = await Promise.all([
    loadProductOverview(token),
    loadProductTimeseries(token),
  ]);

  if (!overviewResult || !seriesResult) {
    errorCode.value = "SERVICE_UNAVAILABLE";
    loading.value = false;
    return;
  }

  overview.value = overviewResult;
  series.value = seriesResult;
  loading.value = false;
}

onMounted(() => {
  void loadProjectAnalytics();
});
</script>

<template>
  <section class="ops-page">
    <header class="page-heading">
      <div>
        <p class="ops-eyebrow">Collaboration</p>
        <h1>项目与协作</h1>
      </div>
      <p>
        生命周期与风险分开解释；Quiet、Completed、Archived
        都不会被粗暴视作流失。这里不生成不透明的 engagement score。
      </p>
    </header>

    <p v-if="loading" class="empty-note">正在读取项目协作分析…</p>
    <p v-else-if="errorCode" class="form-error">
      项目分析暂不可用（{{ errorCode }}）。
    </p>

    <template v-else-if="overview">
      <p
        v-if="overview.coverage.partial"
        class="form-hint"
        data-testid="project-coverage-partial"
      >
        当前窗口早于业务分析完整数据纪元，以下结果包含部分覆盖。
      </p>
      <ActivationFunnel :overview="overview" />
      <ProjectLifecycleSummary :overview="overview" />

      <section class="ops-note">
        <h2>日粒度 Rollup</h2>
        <p>
          已读取 {{ series.length }} 个版本化指标点；
          <template v-if="latestSeriesDate">
            最新数据日期 {{ latestSeriesDate }}。
          </template>
          趋势值直接来自数据库 rollup，不在浏览器重新计算。
        </p>
      </section>
    </template>
  </section>
</template>
