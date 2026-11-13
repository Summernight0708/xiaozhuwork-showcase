<script setup lang="ts">
defineProps<{
  projects: readonly { id: string; name: string }[];
}>();

const mode = defineModel<"all" | "unread">("mode", { required: true });
const projectId = defineModel<string>("projectId", { required: true });
</script>

<template>
  <div class="notification-filters">
    <div class="mode-tabs" role="group" aria-label="通知状态">
      <button
        type="button"
        :aria-pressed="mode === 'all'"
        @click="mode = 'all'"
      >
        全部
      </button>
      <button
        type="button"
        :aria-pressed="mode === 'unread'"
        @click="mode = 'unread'"
      >
        未读
      </button>
    </div>
    <select v-model="projectId" aria-label="项目筛选">
      <option value="all">全部来源</option>
      <option value="system">系统通知</option>
      <option v-for="project in projects" :key="project.id" :value="project.id">
        {{ project.name }}
      </option>
    </select>
  </div>
</template>

<style scoped>
.notification-filters {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 16px;
}
.mode-tabs {
  display: inline-flex;
  gap: var(--space-xs);
  border-bottom: 1px solid var(--tu-border);
}
.mode-tabs button {
  min-height: 36px;
  border: 0;
  border-radius: 0;
  padding: 0 var(--space-xs);
  background: transparent;
  color: var(--tu-muted);
  cursor: pointer;
}
.mode-tabs button[aria-pressed="true"] {
  box-shadow: inset 0 -2px var(--tu-action);
  color: var(--tu-ink);
  font-weight: 650;
}
.notification-filters select {
  min-height: 42px;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  padding: 0 10px;
  background: var(--tu-surface);
  color: var(--tu-ink);
}
@media (max-width: 600px) {
  .notification-filters {
    align-items: stretch;
    flex-direction: column;
  }
  .mode-tabs {
    align-self: flex-start;
  }
}
</style>
