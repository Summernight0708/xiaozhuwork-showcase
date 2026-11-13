<script setup lang="ts">
withDefaults(
  defineProps<{
    activeIssueCount?: number;
    canRequestHelp?: boolean;
    canRequestRework?: boolean;
  }>(),
  {
    activeIssueCount: 0,
    canRequestHelp: false,
    canRequestRework: false,
  },
);

const emit = defineEmits<{
  requestHelp: [];
  requestRework: [];
}>();
</script>

<template>
  <div class="issues">
    <slot>
      <p class="muted">当前没有进行中的求助或返工事项。</p>
    </slot>
    <div v-if="canRequestHelp || canRequestRework" class="issue-actions">
      <button v-if="canRequestHelp" type="button" @click="emit('requestHelp')">
        发起求助
      </button>
      <button
        v-if="canRequestRework"
        type="button"
        @click="emit('requestRework')"
      >
        申请上游返工
      </button>
    </div>
  </div>
</template>

<style scoped>
.issues {
  display: grid;
  gap: 12px;
  padding-top: 16px;
}
.muted {
  color: var(--tu-muted);
}
.issue-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.issue-actions button {
  min-height: 38px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-surface);
  color: var(--tu-blue-strong);
  cursor: pointer;
  padding: 0 12px;
  font-weight: 700;
}
</style>
