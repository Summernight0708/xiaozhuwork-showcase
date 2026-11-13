<script setup lang="ts">
import { computed } from "vue";

import {
  formatPrivateMetric,
  formatPrivateRate,
  isPrivateCohortSuppressed,
} from "@shared/analytics/privacy";

const props = defineProps<{
  label: string;
  value: number;
  sampleSize: number | null;
  rate?: number | null;
}>();

const suppressed = computed(() => isPrivateCohortSuppressed(props.sampleSize));
const valueText = computed(() =>
  formatPrivateMetric(props.value, props.sampleSize),
);
const rateText = computed(() =>
  props.rate === undefined || suppressed.value
    ? null
    : formatPrivateRate(props.rate, props.sampleSize),
);
</script>

<template>
  <section
    class="privacy-metric"
    :data-suppressed="suppressed ? 'true' : 'false'"
  >
    <span class="privacy-metric__label">{{ label }}</span>
    <strong class="privacy-metric__value">{{ valueText }}</strong>
    <span v-if="rateText" class="privacy-metric__rate">{{ rateText }}</span>
  </section>
</template>
