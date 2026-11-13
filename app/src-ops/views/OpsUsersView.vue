<script setup lang="ts">
import AccountSupportLookup from "@ops/components/AccountSupportLookup.vue";
</script>

<template>
  <section class="ops-page">
    <header class="page-heading">
      <div>
        <p class="ops-eyebrow">Support</p>
        <h1>用户与使用</h1>
      </div>
      <p>
        默认只看聚合注册与使用指标。只有处理具体支持问题时才进行精确账号查询。
      </p>
    </header>

    <section class="ops-note">
      <h2>聚合使用指标</h2>
      <p>注册、激活和项目持续协作指标将在 Analytics 数据层接入后显示。</p>
    </section>

    <AccountSupportLookup />
  </section>
</template>
