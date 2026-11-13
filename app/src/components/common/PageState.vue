<script setup lang="ts">
defineProps<{
  loading?: boolean;
  error?: string | null;
  empty?: boolean;
  emptyTitle?: string;
  emptyDescription?: string;
  permissionDenied?: boolean;
  notFoundOrDenied?: boolean;
  disabled?: boolean;
}>();

const emit = defineEmits<{ retry: [] }>();
</script>

<template>
  <div
    v-if="loading"
    class="state-wrap state-loading"
    aria-live="polite"
    aria-busy="true"
  >
    <span class="sr-only">正在加载...</span>
    <div class="state-skeleton" aria-hidden="true">
      <span /><span /><span />
    </div>
  </div>
  <div v-else-if="notFoundOrDenied" class="state-wrap" role="status">
    <p class="state-title">内容不存在，或你没有访问权限</p>
  </div>
  <div v-else-if="permissionDenied" class="state-wrap" role="status">
    <p class="state-title">你没有访问此内容的权限</p>
  </div>
  <div v-else-if="error" class="state-wrap" role="alert">
    <p class="state-title">加载失败</p>
    <p class="state-description">{{ error }}</p>
    <van-button size="small" type="primary" plain @click="emit('retry')"
      >重试</van-button
    >
  </div>
  <div v-else-if="disabled" class="state-wrap" role="status">
    <p class="state-title">此能力当前尚未启用</p>
  </div>
  <div v-else-if="empty" class="state-wrap" role="status">
    <p class="state-title">{{ emptyTitle || "暂时没有内容" }}</p>
    <p v-if="emptyDescription" class="state-description">
      {{ emptyDescription }}
    </p>
    <slot name="empty-action" />
  </div>
  <slot v-else />
</template>

<style scoped>
.state-wrap {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--space-sm);
  min-height: 156px;
  padding: var(--space-2xl) var(--space-md);
  border-top: 1px solid var(--tu-border);
  color: var(--tu-muted);
  text-align: center;
}
.state-title {
  margin: 0;
  font-size: var(--text-sm);
  font-weight: 500;
}
.state-description {
  max-width: 52ch;
  margin: 0;
  font-size: var(--text-sm);
  overflow-wrap: anywhere;
}
.state-loading {
  align-items: stretch;
}
.state-skeleton {
  display: grid;
  gap: var(--space-sm);
  width: min(520px, 100%);
  margin: auto;
}
.state-skeleton span {
  height: 12px;
  background: var(--tu-subtle-surface);
  animation: state-pulse 1.3s ease-in-out infinite alternate;
}
.state-skeleton span:nth-child(2) {
  width: 82%;
}
.state-skeleton span:nth-child(3) {
  width: 64%;
}
@keyframes state-pulse {
  from {
    opacity: 0.5;
  }
  to {
    opacity: 1;
  }
}
@media (prefers-reduced-motion: reduce) {
  .state-skeleton span {
    animation: none;
  }
}
</style>
