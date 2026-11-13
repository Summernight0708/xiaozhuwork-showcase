<script setup lang="ts">
import { onMounted, ref } from "vue";

import ProductOverview from "@ops/features/analytics/ProductOverview.vue";
import type { ProductAnalyticsOverviewV1 } from "@ops/features/analytics/contracts";
import { loadProductOverview } from "@ops/features/analytics/api";
import { useOpsAuthStore } from "@ops/stores/auth";

const auth = useOpsAuthStore();
const loading = ref(true);
const errorCode = ref<string | null>(null);
const overview = ref<ProductAnalyticsOverviewV1 | null>(null);

async function loadOverview() {
  loading.value = true;
  errorCode.value = null;

  const token = auth.session?.access_token;
  if (!token) {
    errorCode.value = "UNAUTHENTICATED";
    loading.value = false;
    return;
  }

  const result = await loadProductOverview(token);
  if (!result) {
    errorCode.value = "SERVICE_UNAVAILABLE";
    loading.value = false;
    return;
  }

  overview.value = result;
  loading.value = false;
}
onMounted(() => {
  void loadOverview();
});
</script>

<template>
  <section class="ops-page">
    <header class="page-heading">
      <div>
        <p class="ops-eyebrow">Beta Operations</p>
        <h1>总览</h1>
      </div>
      <p>
        产品分析以 XiaozhuWork 数据库中的业务事实为准；流量看 Umami，故障看
        Sentry，不把三类数据混成一个“活跃分数”。
      </p>
    </header>

    <p v-if="loading" class="empty-note">正在读取产品分析…</p>
    <p v-else-if="errorCode" class="form-error">
      产品分析暂不可用（{{ errorCode }}）。
    </p>
    <ProductOverview v-else-if="overview" :overview="overview" />

    <section class="ops-note">
      <h2>外部观测</h2>
      <p>
        访问量、来源与匿名页面行为请到 Umami；异常与可靠性请到 Sentry。
        此页只展示 XiaozhuWork 数据库可以证明的业务事实。
      </p>
      <RouterLink :to="{ name: 'ops-system' }">前往商业与系统入口</RouterLink>
    </section>
  </section>
</template>
