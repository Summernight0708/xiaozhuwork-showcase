<script setup lang="ts">
import type { TaskCurrentAction } from "@/types/frontend-integration";

withDefaults(
  defineProps<{
    title: string;
    status: string;
    primaryName: string;
    collaboratorNames?: readonly string[];
    deadlineAt: string;
    weight?: number | null;
    currentAction?: TaskCurrentAction | null;
    compact?: boolean;
  }>(),
  {
    collaboratorNames: () => [],
    weight: 1,
    currentAction: null,
    compact: false,
  },
);

const emit = defineEmits<{
  action: [action: TaskCurrentAction];
}>();
</script>

<template>
  <header class="task-detail-header" :class="{ compact }">
    <div class="header-main">
      <div class="status-line">
        <span class="status-badge">{{ status }}</span>
        <span
          class="stars"
          :aria-label="
            '任务难度 ' + Math.max(1, Math.round(weight || 1)) + '/5'
          "
        >
          {{ "★".repeat(Math.max(1, Math.round(weight || 1))) }}
        </span>
      </div>
      <h1>{{ title }}</h1>
      <div class="header-facts">
        <span><b>主负责人</b>{{ primaryName }}</span>
        <span>
          <b>协作者</b>
          {{
            collaboratorNames.length
              ? collaboratorNames.slice(0, 2).join("、") +
                (collaboratorNames.length > 2
                  ? " +" + (collaboratorNames.length - 2)
                  : "")
              : "暂无"
          }}
        </span>
        <span><b>DDL</b>{{ new Date(deadlineAt).toLocaleString() }}</span>
      </div>
    </div>
    <button
      v-if="currentAction"
      type="button"
      class="current-action"
      @click="emit('action', currentAction)"
    >
      {{ currentAction.label }}
    </button>
  </header>
</template>

<style scoped>
.task-detail-header {
  display: flex;
  justify-content: space-between;
  gap: 20px;
  align-items: flex-end;
  padding: var(--space-lg) 0;
  border-bottom: 1px solid var(--tu-border);
  background: transparent;
}
.task-detail-header.compact {
  padding: var(--space-md) 0;
}
.header-main {
  min-width: 0;
}
.status-line {
  display: flex;
  gap: 10px;
  align-items: center;
}
.status-badge {
  color: var(--tu-blue-strong);
  font-weight: 800;
}
.stars {
  color: var(--tu-star);
  letter-spacing: 1px;
}
h1 {
  margin: 7px 0 10px;
  font-size: clamp(24px, 4vw, 36px);
  overflow-wrap: anywhere;
}
.header-facts {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 18px;
  color: var(--tu-muted);
  font-size: 13px;
}
.header-facts span {
  display: inline-flex;
  gap: 5px;
}
.header-facts b {
  color: var(--tu-ink);
}
.current-action {
  flex: none;
  min-height: 44px;
  padding: 0 16px;
  border: 0;
  border-radius: var(--radius-control);
  background: var(--tu-action);
  color: var(--tu-action-contrast);
  cursor: pointer;
  font-weight: 800;
}
@media (hover: hover) {
  .current-action:hover {
    background: var(--tu-action-hover);
  }
}
.current-action:active {
  background: var(--tu-action-active);
}
@media (max-width: 640px) {
  .task-detail-header {
    align-items: stretch;
    flex-direction: column;
  }
  .current-action {
    width: 100%;
  }
}
</style>
