<script setup lang="ts">
defineProps<{
  released: boolean;
  entitled: boolean;
  projectState: "free" | "active" | "grace" | "unknown";
  viewerRole: string;
}>();
</script>

<template>
  <section class="surface delegation-status" role="status">
    <h2>权限生效状态</h2>
    <p v-if="!released">高级权限尚未发布。原有组长和管理员权限不受影响。</p>
    <p v-else-if="!entitled">
      项目当前不满足 Pro / 宽限期条件，已授权模板暂时失效，但记录保留。
    </p>
    <p v-else>高级权限可用；只有活动普通成员的未撤销模板会生效。</p>
    <p class="detail">
      项目套餐状态：{{
        projectState === "active"
          ? "Pro"
          : projectState === "grace"
            ? "宽限期"
            : projectState === "free"
              ? "Free"
              : "读取中"
      }}
      · 当前基础角色：{{ viewerRole }}
    </p>
  </section>
</template>

<style scoped>
.delegation-status {
  padding: 1rem;
}
.detail {
  color: var(--tu-muted);
  font-size: 0.875rem;
}
</style>
