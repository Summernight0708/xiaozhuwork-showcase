<script setup lang="ts">
import type { TaskAlertPresentation } from "@/types/frontend-integration";

defineProps<{
  alerts: readonly TaskAlertPresentation[];
}>();
</script>

<template>
  <div v-if="alerts.length" class="task-alerts" aria-live="polite">
    <article
      v-for="alert in alerts"
      :key="alert.id"
      class="task-alert"
      :class="'tone-' + alert.tone"
      role="status"
    >
      <strong>{{ alert.label }}</strong>
      <span v-if="alert.detail">{{ alert.detail }}</span>
    </article>
  </div>
</template>

<style scoped>
.task-alerts {
  display: grid;
  gap: 8px;
}
.task-alert {
  display: grid;
  gap: 3px;
  padding: 12px 14px;
  border-left: 2px solid var(--tu-border);
  background: transparent;
}
.task-alert span {
  color: var(--tu-muted);
}
.tone-warning {
  border-color: var(--tu-border);
  background: var(--tu-warning-surface);
}
.tone-danger {
  border-color: var(--tu-border);
  background: var(--tu-danger-surface);
}
.tone-info {
  border-color: var(--tu-border);
  background: var(--tu-blue-soft);
}
</style>
