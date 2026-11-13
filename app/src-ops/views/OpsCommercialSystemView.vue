<script setup lang="ts">
const umamiUrl =
  import.meta.env.VITE_OPS_UMAMI_URL?.trim() ||
  "https://analytics.xiaozhuwork.com";
const sentryUrl =
  import.meta.env.VITE_OPS_SENTRY_URL?.trim() || "https://sentry.io/";
</script>

<template>
  <section class="ops-page">
    <header class="page-heading">
      <div>
        <p class="ops-eyebrow">Commercial & Reliability</p>
        <h1>商业与系统</h1>
      </div>
      <p>
        Free / Pro
        只做聚合事实；流量和错误分别跳转到专门系统，避免混成一套指标。
      </p>
    </header>

    <section class="system-links">
      <a :href="umamiUrl" target="_blank" rel="noreferrer">
        <strong>Umami</strong>
        <span>匿名流量与前端访问行为</span>
      </a>
      <a :href="sentryUrl" target="_blank" rel="noreferrer">
        <strong>Sentry</strong>
        <span>错误、故障和请求关联</span>
      </a>
    </section>

    <section class="ops-note">
      <h2>Free / Pro</h2>
      <p>
        商业漏斗和权益来源只在数据可证明时显示；测试、赠送和人工付费来源不得混为一类。
      </p>
    </section>
  </section>
</template>
