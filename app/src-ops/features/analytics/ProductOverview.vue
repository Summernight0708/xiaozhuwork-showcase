<script setup lang="ts">
import { computed } from "vue";

import PrivacyMetric from "@ops/components/PrivacyMetric.vue";
import type { ProductAnalyticsOverviewV1 } from "@ops/features/analytics/contracts";

const props = defineProps<{
  overview: ProductAnalyticsOverviewV1;
}>();

const coverageStart = computed(
  () =>
    props.overview.coverage.businessAnalyticsCompleteSince?.slice(0, 10) ??
    "尚未验证",
);
</script>

<template>
  <section class="product-overview" aria-label="Beta 产品分析总览">
    <div class="product-overview__north-star" data-testid="wacp-north-star">
      <div>
        <p>北极星指标</p>
        <h2>WACP</h2>
        <span>本周发生真实多人协作的有效项目</span>
      </div>
      <PrivacyMetric
        label="Weekly Active Collaborative Projects"
        :value="overview.wacp.value"
        :sample-size="null"
      />
    </div>

    <p
      class="product-overview__coverage"
      data-testid="coverage-status"
      :data-partial="overview.coverage.partial ? 'true' : 'false'"
    >
      <strong>{{ overview.coverage.partial ? "部分覆盖" : "完整覆盖" }}</strong>
      <span>业务分析完整数据自 {{ coverageStart }}</span>
    </p>

    <div class="product-overview__diagnostics">
      <PrivacyMetric
        label="项目激活"
        :value="overview.projectActivation.numerator"
        :sample-size="overview.projectActivation.denominator"
        :rate="overview.projectActivation.rate"
      />
      <PrivacyMetric
        label="用户激活"
        :value="overview.userActivation.numerator"
        :sample-size="overview.userActivation.denominator"
        :rate="overview.userActivation.rate"
      />
      <PrivacyMetric
        label="First Value"
        :value="overview.firstValueRate.numerator"
        :sample-size="overview.firstValueRate.denominator"
        :rate="overview.firstValueRate.rate"
      />
      <PrivacyMetric
        label="核心闭环完成"
        :value="overview.coreLoopCompleted"
        :sample-size="null"
      />
      <PrivacyMetric
        label="项目完成"
        :value="overview.projectCompletion.numerator"
        :sample-size="overview.projectCompletion.denominator"
        :rate="overview.projectCompletion.rate"
      />
    </div>
  </section>
</template>

<style scoped>
.product-overview {
  margin-top: 34px;
}

.product-overview__north-star {
  padding: 22px 2px 26px;
  border-top: 3px solid #202a32;
  border-bottom: 1px solid #cfd3d1;
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 40px;
  align-items: end;
}

.product-overview__north-star p,
.product-overview__north-star span {
  margin: 0;
  color: #68737b;
}

.product-overview__north-star h2 {
  margin: 4px 0 6px;
  font-size: clamp(2.2rem, 5vw, 4.2rem);
  line-height: 0.98;
  letter-spacing: -0.05em;
}

.product-overview__coverage {
  margin: 0;
  padding: 14px 2px;
  border-bottom: 1px solid #d9dcda;
  display: flex;
  gap: 18px;
  color: #68737b;
  font-size: 0.88rem;
}

.product-overview__coverage[data-partial="true"] strong {
  color: #8a5a16;
}

.product-overview__diagnostics {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  border-bottom: 1px solid #cfd3d1;
}

.product-overview__diagnostics :deep(.privacy-metric) {
  min-height: 112px;
  padding: 22px 18px 20px 2px;
  border-right: 1px solid #d9dcda;
}

.product-overview__diagnostics :deep(.privacy-metric:last-child) {
  border-right: 0;
}

@media (max-width: 900px) {
  .product-overview__diagnostics {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .product-overview__north-star {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 560px) {
  .product-overview__diagnostics {
    grid-template-columns: 1fr;
  }

  .product-overview__coverage {
    display: grid;
    gap: 4px;
  }
}
</style>
