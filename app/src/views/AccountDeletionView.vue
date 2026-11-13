<script setup lang="ts">
import AccountDeletionFlow from "@/components/account/AccountDeletionFlow.vue";
</script>

<template>
  <main class="xiaozhuwork-page">
    <header class="page-heading">
      <div>
        <h1>账号注销与撤销</h1>
        <p>本流程由服务端核验项目责任，撤销窗口为申请后的 30 天。</p>
      </div>
    </header>
    <AccountDeletionFlow />
  </main>
</template>
