<script setup lang="ts">
import type { WorkTaskItem } from "@/domain/todo-workboard";

defineProps<{
  item: WorkTaskItem;
  showProject?: boolean;
}>();

const emit = defineEmits<{
  open: [item: WorkTaskItem];
}>();

function deadlineLabel(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "DDL 未知"
    : `DDL ${date.toLocaleDateString("zh-CN", {
        month: "2-digit",
        day: "2-digit",
      })}`;
}
</script>

<template>
  <button
    type="button"
    class="work-task-card"
    :class="{
      'is-needs-changes': item.needsChanges,
      'is-overdue': item.overdue,
    }"
    @click="emit('open', item)"
  >
    <span v-if="showProject" class="project-context">{{
      item.projectName
    }}</span>
    <strong>{{ item.task.title }}</strong>
    <span class="card-meta">
      <span
        v-if="item.responsibility"
        class="responsibility"
        :class="`is-${item.responsibility.kind}`"
      >
        {{ item.responsibility.kind === "primary" ? "主负责" : "协作" }}
      </span>
      <span v-if="item.responsibility?.collaboratorCount" class="collaborators">
        +{{ item.responsibility.collaboratorCount }}
      </span>
      <span>{{ deadlineLabel(item.task.deadline_at) }}</span>
    </span>
    <span class="status-row">
      <span class="status-badge">{{ item.statusLabel }}</span>
      <span v-if="item.overdue" class="attention-badge">已逾期</span>
      <span v-else-if="item.dueSoon" class="attention-badge">即将到期</span>
    </span>
    <small v-if="item.statusDetail">{{ item.statusDetail }}</small>
  </button>
</template>

<style scoped>
.work-task-card {
  width: 100%;
  display: grid;
  gap: 8px;
  min-width: 0;
  padding: var(--space-sm) 0;
  border: 0;
  border-bottom: 1px solid var(--tu-border);
  background: transparent;
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.work-task-card:hover {
  background: var(--tu-subtle-surface);
}
.work-task-card:focus-visible {
  outline: 2px solid var(--tu-focus-ring);
  outline-offset: 2px;
}
.work-task-card.is-needs-changes strong {
  color: var(--tu-warning-ink);
}
.work-task-card.is-overdue strong {
  color: var(--tu-danger);
}
.project-context,
.card-meta,
.work-task-card small {
  color: var(--tu-muted);
  font-size: 12px;
}
.card-meta,
.status-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 7px;
}
.responsibility,
.status-badge,
.attention-badge {
  display: inline-flex;
  align-items: center;
  min-height: 22px;
  padding: 2px 7px;
  font-size: 11px;
  font-weight: 700;
}
.responsibility {
  color: var(--tu-blue-strong);
}
.responsibility.is-collaborator {
  color: var(--tu-muted);
}
.status-badge {
  color: var(--tu-muted);
}
.attention-badge {
  color: var(--tu-warning-ink);
}
.work-task-card small {
  line-height: 1.45;
}
</style>
