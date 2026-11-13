<script setup lang="ts">
import PrivacyMetric from "@ops/components/PrivacyMetric.vue";
import type { ProductAnalyticsOverviewV1 } from "@ops/features/analytics/contracts";

defineProps<{
  overview: ProductAnalyticsOverviewV1;
}>();
</script>

<template>
  <section class="lifecycle-summary" aria-label="项目生命周期">
    <header>
      <h2>项目生命周期</h2>
      <p>Quiet、Completed、Archived 均保留独立含义，不折叠为“流失”。</p>
    </header>
    <div class="lifecycle-summary__metrics">
      <PrivacyMetric
        label="Setup"
        :value="overview.lifecycle.setup"
        :sample-size="overview.projectActivation.denominator"
      />
      <PrivacyMetric
        label="协作中"
        :value="overview.lifecycle.collaborating"
        :sample-size="overview.projectActivation.denominator"
      />
      <PrivacyMetric
        label="Quiet"
        :value="overview.lifecycle.quiet"
        :sample-size="overview.projectActivation.denominator"
      />
      <PrivacyMetric
        label="Stalled"
        :value="overview.lifecycle.stalled"
        :sample-size="overview.projectActivation.denominator"
      />
      <PrivacyMetric
        label="已完成"
        :value="overview.lifecycle.completed"
        :sample-size="overview.projectActivation.denominator"
      />
      <PrivacyMetric
        label="已归档"
        :value="overview.lifecycle.archived"
        :sample-size="overview.projectActivation.denominator"
      />
    </div>
  </section>
</template>

<style scoped>
.lifecycle-summary {
  margin-top: 42px;
  padding-top: 22px;
  border-top: 3px solid #202a32;
}

.lifecycle-summary header {
  display: flex;
  justify-content: space-between;
  gap: 32px;
}

.lifecycle-summary h2,
.lifecycle-summary p {
  margin: 0;
}

.lifecycle-summary p {
  max-width: 520px;
  color: #68737b;
  line-height: 1.65;
}

.lifecycle-summary__metrics {
  margin-top: 22px;
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  border-top: 1px solid #d9dcda;
}

.lifecycle-summary__metrics :deep(.privacy-metric) {
  min-height: 98px;
  padding: 18px 18px 18px 2px;
  border-bottom: 1px solid #d9dcda;
}

@media (max-width: 700px) {
  .lifecycle-summary header,
  .lifecycle-summary__metrics {
    display: grid;
    grid-template-columns: 1fr;
  }
}
</style>
