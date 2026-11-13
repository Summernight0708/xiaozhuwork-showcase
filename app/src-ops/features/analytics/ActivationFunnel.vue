<script setup lang="ts">
import PrivacyMetric from "@ops/components/PrivacyMetric.vue";
import type { ProductAnalyticsOverviewV1 } from "@ops/features/analytics/contracts";

defineProps<{
  overview: ProductAnalyticsOverviewV1;
}>();
</script>

<template>
  <section class="activation-funnel" aria-label="Activation 与 First Value">
    <header>
      <h2>协作激活</h2>
      <p>Activation 与 First Value 只解释真实业务闭环，不使用页面点击替代。</p>
    </header>
    <div class="activation-funnel__metrics">
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
    </div>
  </section>
</template>

<style scoped>
.activation-funnel {
  margin-top: 42px;
  padding-top: 22px;
  border-top: 3px solid #202a32;
}

.activation-funnel header {
  display: flex;
  justify-content: space-between;
  gap: 32px;
}

.activation-funnel h2,
.activation-funnel p {
  margin: 0;
}

.activation-funnel p {
  max-width: 540px;
  color: #68737b;
  line-height: 1.65;
}

.activation-funnel__metrics {
  margin-top: 22px;
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  border-top: 1px solid #d9dcda;
  border-bottom: 1px solid #d9dcda;
}

.activation-funnel__metrics :deep(.privacy-metric) {
  min-height: 108px;
  padding: 20px 18px 18px 2px;
  border-right: 1px solid #d9dcda;
}

.activation-funnel__metrics :deep(.privacy-metric:last-child) {
  border-right: 0;
}

@media (max-width: 700px) {
  .activation-funnel header,
  .activation-funnel__metrics {
    display: grid;
    grid-template-columns: 1fr;
  }
}
</style>
