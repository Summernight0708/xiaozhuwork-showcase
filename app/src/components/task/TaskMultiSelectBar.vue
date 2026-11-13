<script setup lang="ts">
withDefaults(
  defineProps<{
    count: number;
    canBulkUpdateStatus?: boolean;
  }>(),
  { canBulkUpdateStatus: false },
);

const emit = defineEmits<{
  cancel: [];
  changeStatus: [];
}>();
</script>

<template>
  <div class="multi-select-bar" role="region" aria-label="任务批量操作">
    <strong>已选择 {{ count }} 项</strong>
    <span v-if="!canBulkUpdateStatus" class="muted"
      >当前没有可用的批量操作。</span
    >
    <div class="actions">
      <button
        v-if="canBulkUpdateStatus"
        type="button"
        :disabled="count === 0"
        @click="emit('changeStatus')"
      >
        修改状态
      </button>
      <button type="button" @click="emit('cancel')">取消</button>
    </div>
  </div>
</template>

<style scoped>
.multi-select-bar {
  position: sticky;
  bottom: 14px;
  z-index: 3;
  display: flex;
  align-items: center;
  gap: 12px;
  margin-top: 14px;
  padding: 12px 14px;
  border: 1px solid var(--tu-border);
  border-radius: 12px;
  background: var(--tu-surface);
  box-shadow: var(--tu-shadow);
}
.multi-select-bar .muted {
  flex: 1;
  font-size: 13px;
}
.actions {
  display: flex;
  gap: 8px;
  margin-left: auto;
}
.actions button {
  min-height: 38px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  padding: 0 12px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  cursor: pointer;
}
@media (max-width: 600px) {
  .multi-select-bar {
    flex-wrap: wrap;
  }
  .multi-select-bar .muted {
    flex-basis: 100%;
  }
  .actions {
    width: 100%;
  }
  .actions button {
    flex: 1;
  }
}
</style>
