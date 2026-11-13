<script setup lang="ts">
import { computed } from "vue";

import {
  formatAccountEntitlement,
  type AccountEntitlement,
} from "@/domain/entitlements";

const props = defineProps<{
  entitlement: AccountEntitlement;
}>();

const presentation = computed(() =>
  formatAccountEntitlement(props.entitlement),
);
</script>

<template>
  <section class="account-plan-summary" aria-labelledby="account-plan-title">
    <div class="plan-copy">
      <h2 id="account-plan-title">当前账号方案</h2>
      <p class="plan-label">{{ presentation.label }}</p>
      <p class="plan-detail">{{ presentation.detail }}</p>
    </div>
    <div class="current-plan-fact">
      <span>当前有效方案</span>
      <strong>{{ presentation.currentPlanLabel }}</strong>
    </div>
  </section>
</template>

<style scoped>
.account-plan-summary {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 28px;
  align-items: center;
  padding: var(--space-lg) 0;
  border-top: 1px solid var(--tu-border);
  border-bottom: 1px solid var(--tu-border);
}
.plan-copy {
  min-width: 0;
}
.plan-copy h2 {
  margin: 0 0 12px;
  font-size: 18px;
}
.plan-label {
  margin: 0;
  color: var(--tu-ink);
  font-size: clamp(26px, 4vw, 36px);
  font-weight: 800;
  letter-spacing: -0.035em;
  text-wrap: balance;
}
.plan-detail {
  max-width: 68ch;
  margin: 10px 0 0;
  color: var(--tu-muted);
  line-height: 1.7;
}
.current-plan-fact {
  min-width: 150px;
  padding-left: 24px;
  border-left: 1px solid var(--tu-border);
}
.current-plan-fact span,
.current-plan-fact strong {
  display: block;
}
.current-plan-fact span {
  color: var(--tu-muted);
  font-size: 13px;
}
.current-plan-fact strong {
  margin-top: 6px;
  font-size: 18px;
}
@media (max-width: 640px) {
  .account-plan-summary {
    grid-template-columns: 1fr;
    gap: 18px;
    padding: var(--space-sm) 0;
  }
  .current-plan-fact {
    min-width: 0;
    padding: 16px 0 0;
    border-top: 1px solid var(--tu-border);
    border-left: 0;
  }
}
</style>
