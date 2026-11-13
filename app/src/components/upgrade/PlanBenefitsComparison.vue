<script setup lang="ts">
import { computed } from "vue";

import {
  PLAN_BENEFITS,
  benefitStatusLabel,
  shouldShowBenefitStatus,
  type BenefitReleaseStatus,
  type PlanBenefit,
} from "./planBenefits";

const props = defineProps<{
  benefits?: readonly PlanBenefit[];
}>();

const benefitItems = computed(() => props.benefits ?? PLAN_BENEFITS);
const hasUnreleasedBenefits = computed(() =>
  shouldShowBenefitStatus(benefitItems.value),
);

function releaseStatusClass(status: BenefitReleaseStatus) {
  if (status === "released") return "release-status--released";
  if (status === "integration_pending") {
    return "release-status--integration-pending";
  }
  return "release-status--planned";
}
</script>

<template>
  <section class="benefits-section" aria-labelledby="benefits-title">
    <div class="section-heading">
      <div>
        <h2 id="benefits-title">Free 与 Pro 权益</h2>
        <p v-if="hasUnreleasedBenefits">未正式上线的能力会标注当前状态。</p>
        <p v-else>以下权益均已正式上线。</p>
      </div>
    </div>

    <div class="benefits-table-wrap">
      <table class="benefits-table">
        <thead>
          <tr>
            <th scope="col">权益</th>
            <th scope="col">Free</th>
            <th scope="col">Pro</th>
            <th v-if="hasUnreleasedBenefits" scope="col">状态</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="benefit in benefitItems" :key="benefit.name">
            <th scope="row">{{ benefit.name }}</th>
            <td>{{ benefit.free }}</td>
            <td>{{ benefit.pro }}</td>
            <td v-if="hasUnreleasedBenefits">
              <span
                class="release-status"
                :class="releaseStatusClass(benefit.status)"
              >
                {{ benefitStatusLabel(benefit.status) }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="benefits-mobile" aria-label="Free 与 Pro 权益移动端对比">
      <article
        v-for="benefit in benefitItems"
        :key="benefit.name"
        class="benefit-card"
      >
        <div class="benefit-card-heading">
          <h3>{{ benefit.name }}</h3>
          <span
            v-if="hasUnreleasedBenefits"
            class="release-status"
            :class="releaseStatusClass(benefit.status)"
          >
            {{ benefitStatusLabel(benefit.status) }}
          </span>
        </div>
        <dl>
          <div>
            <dt>Free</dt>
            <dd>{{ benefit.free }}</dd>
          </div>
          <div>
            <dt>Pro</dt>
            <dd>{{ benefit.pro }}</dd>
          </div>
        </dl>
      </article>
    </div>

    <p class="project-pro-note">
      Pro 账号以组长、管理员或成员身份参与项目时，可以使该项目获得 Pro
      项目权益；观察者身份不触发项目 Pro。
    </p>
  </section>
</template>

<style scoped>
.benefits-section {
  margin-top: 28px;
}
.section-heading {
  margin-bottom: 14px;
}
.section-heading h2 {
  margin: 0;
  font-size: 22px;
  text-wrap: balance;
}
.section-heading p {
  max-width: 70ch;
  margin: 7px 0 0;
  color: var(--tu-muted);
  line-height: 1.65;
}
.benefits-table-wrap {
  overflow: hidden;
  border-top: 1px solid var(--tu-border);
}
.benefits-table {
  width: 100%;
  border-collapse: collapse;
  font-variant-numeric: tabular-nums;
}
.benefits-table th,
.benefits-table td {
  padding: 14px 16px;
  border-bottom: 1px solid var(--tu-border);
  text-align: left;
  vertical-align: top;
}
.benefits-table thead th {
  color: var(--tu-muted);
  font-size: 13px;
  font-weight: 650;
}
.benefits-table tbody th {
  width: 28%;
  color: var(--tu-ink);
  font-weight: 650;
}
.benefits-table tbody tr:last-child th,
.benefits-table tbody tr:last-child td {
  border-bottom: 0;
}
.release-status {
  display: inline-flex;
  min-height: 26px;
  align-items: center;
  padding: 3px 8px;
  border-bottom: 1px solid var(--tu-border);
  color: var(--tu-muted);
  font-size: 12px;
  font-weight: 650;
  white-space: nowrap;
}
.release-status--released {
  border-color: color-mix(in srgb, var(--tu-success) 35%, var(--tu-border));
  color: var(--tu-success);
}
.release-status--integration-pending {
  border-color: color-mix(in srgb, var(--tu-warning) 35%, var(--tu-border));
  color: var(--tu-warning);
}
.benefits-mobile {
  display: none;
}
.project-pro-note {
  margin: 14px 0 0;
  color: var(--tu-muted);
  line-height: 1.7;
}
@media (max-width: 720px) {
  .benefits-table-wrap {
    display: none;
  }
  .benefits-mobile {
    display: grid;
    gap: 10px;
  }
  .benefit-card {
    padding: var(--space-md) 0;
    border-top: 1px solid var(--tu-border);
  }
  .benefit-card-heading {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 14px;
  }
  .benefit-card h3 {
    margin: 0;
    font-size: 16px;
  }
  .benefit-card dl {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 12px;
    margin: 14px 0 0;
  }
  .benefit-card dl div {
    min-width: 0;
    padding-top: 10px;
    border-top: 1px solid var(--tu-border);
  }
  .benefit-card dt {
    color: var(--tu-muted);
    font-size: 12px;
  }
  .benefit-card dd {
    margin: 5px 0 0;
    overflow-wrap: anywhere;
    font-weight: 650;
  }
}
</style>
