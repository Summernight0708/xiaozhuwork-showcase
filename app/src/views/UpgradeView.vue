<script setup lang="ts">
import { onMounted, ref } from "vue";

import PageState from "@/components/common/PageState.vue";
import AccountPlanSummary from "@/components/upgrade/AccountPlanSummary.vue";
import ManualUpgradeSection from "@/components/upgrade/ManualUpgradeSection.vue";
import PlanBenefitsComparison from "@/components/upgrade/PlanBenefitsComparison.vue";
import ProValueThemes from "@/components/upgrade/ProValueThemes.vue";
import type { AccountEntitlement } from "@/domain/entitlements";
import { getBackend } from "@/services/backend";
import { unknownErrorMessage } from "@/services/errors";
import { createRepository } from "@/services/repository";

const entitlement = ref<AccountEntitlement | null>(null);
const loading = ref(true);
const error = ref<string | null>(null);
const wechatId = "your_wechat_id";

async function load() {
  const backend = getBackend();
  loading.value = true;
  error.value = null;
  entitlement.value = null;

  try {
    if (!backend) throw new Error("Backend unavailable");
    entitlement.value = await createRepository(
      backend.client,
    ).getMyAccountEntitlement();
  } catch (caught) {
    error.value = unknownErrorMessage(caught);
  } finally {
    loading.value = false;
  }
}

onMounted(() => void load());
</script>

<template>
  <div class="xiaozhuwork-page upgrade-page">
    <header class="page-heading upgrade-heading">
      <div>
        <h1>方案与升级</h1>
      </div>
    </header>

    <PageState :loading="loading" :error="error" @retry="load">
      <template v-if="entitlement">
        <AccountPlanSummary :entitlement="entitlement" />
        <ManualUpgradeSection :wechat-id="wechatId" />
        <PlanBenefitsComparison />
        <ProValueThemes />
      </template>
    </PageState>
  </div>
</template>

<style scoped>
.upgrade-page {
  width: 100%;
  max-width: none;
}
.upgrade-heading {
  max-width: 760px;
}
.upgrade-heading p {
  line-height: 1.7;
  text-wrap: pretty;
}
</style>
