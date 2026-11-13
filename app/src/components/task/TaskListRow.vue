<script setup lang="ts">
import { computed } from "vue";

import StatusBadge from "@/components/common/StatusBadge.vue";

const props = withDefaults(
  defineProps<{
    title: string;
    status: string;
    primaryName: string;
    currentUserIsPrimary?: boolean;
    currentUserIsCollaborator?: boolean;
    collaboratorCount?: number;
    weight?: number | null;
    deadlineAt: string;
    alert?: string | null;
    selectionMode?: boolean;
    selected?: boolean;
    completed?: boolean;
  }>(),
  {
    currentUserIsPrimary: false,
    currentUserIsCollaborator: false,
    collaboratorCount: 0,
    weight: 1,
    alert: null,
    selectionMode: false,
    selected: false,
    completed: false,
  },
);

const emit = defineEmits<{
  open: [];
  toggleSelection: [];
}>();

const stars = computed(() =>
  Math.max(1, Math.min(5, Math.round(props.weight || 1))),
);
const responsibility = computed(() => {
  if (props.currentUserIsPrimary) return "你 · 主负责";
  if (!props.primaryName || props.primaryName === "未分配") return "待认领";
  return `${props.primaryName} · 主负责`;
});
const deadlineLabel = computed(() =>
  new Date(props.deadlineAt).toLocaleDateString("zh-CN", {
    month: "numeric",
    day: "numeric",
  }),
);
</script>

<template>
  <article
    class="task-row"
    :class="{
      completed,
      selected: selectionMode && selected,
      'selection-mode': selectionMode,
    }"
    :aria-selected="selectionMode ? selected : undefined"
  >
    <label v-if="selectionMode" class="selection-control">
      <input
        type="checkbox"
        :checked="selected"
        :aria-label="`选择任务：${title}`"
        @change="emit('toggleSelection')"
      />
    </label>

    <button class="task-main" type="button" @click="emit('open')">
      <span class="task-title">{{ title }}</span>
      <span class="task-status">
        <StatusBadge :status="status" />
        <span v-if="alert" class="task-alert">{{ alert }}</span>
      </span>
      <span class="task-responsibility">
        {{ responsibility }}
        <span v-if="currentUserIsCollaborator" class="collaboration-note"
          >你参与协作</span
        >
        <span v-else-if="collaboratorCount > 0" class="collaboration-note">
          +{{ collaboratorCount }} 协作者
        </span>
      </span>
      <span class="task-meta">
        <span class="stars" :aria-label="`任务难度 ${stars}/5`" role="img"
          >{{ "★".repeat(stars) }}{{ "☆".repeat(5 - stars) }}</span
        >
        <span>DDL {{ deadlineLabel }}</span>
      </span>
      <span class="task-chevron" aria-hidden="true">›</span>
    </button>
  </article>
</template>

<style scoped>
.task-row {
  display: block;
  align-items: stretch;
  border-bottom: 1px solid var(--tu-border);
  background: var(--tu-surface);
}
.task-row.selection-mode {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
}
.task-row:last-child {
  border-bottom: 0;
}
.task-row.completed {
  opacity: 0.62;
}
.task-row.selected {
  background: var(--tu-blue-soft);
}
.selection-control {
  display: grid;
  place-items: center;
  padding-left: 16px;
}
.selection-control input {
  width: 18px;
  height: 18px;
}
.task-main {
  width: 100%;
  min-height: 82px;
  display: grid;
  grid-template-columns:
    minmax(180px, 1.6fr) minmax(150px, 0.8fr) minmax(160px, 1fr)
    minmax(150px, auto) 20px;
  align-items: center;
  gap: 16px;
  padding: 14px 18px;
  border: 0;
  background: transparent;
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.task-main:hover {
  background: color-mix(in srgb, var(--tu-blue-soft) 45%, transparent);
}
.task-title {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  font-size: 16px;
  font-weight: 700;
  white-space: nowrap;
}
.task-status {
  display: grid;
  justify-items: start;
  gap: 4px;
}
.task-alert {
  max-width: 190px;
  overflow: hidden;
  color: var(--tu-danger);
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.task-responsibility {
  display: grid;
  gap: 3px;
  color: var(--tu-ink);
  font-size: 14px;
}
.collaboration-note {
  color: var(--tu-muted);
  font-size: 12px;
}
.task-meta {
  display: grid;
  justify-items: start;
  gap: 4px;
  color: var(--tu-muted);
  font-size: 13px;
}
.stars {
  color: var(--tu-star);
}
.task-chevron {
  color: var(--tu-muted);
  font-size: 24px;
}
@media (max-width: 760px) {
  .task-main {
    min-height: 112px;
    grid-template-columns: minmax(0, 1fr) auto;
    grid-template-areas:
      "title chevron"
      "status chevron"
      "responsibility chevron"
      "meta chevron";
    gap: 5px 12px;
    padding: 14px;
  }
  .task-title {
    grid-area: title;
  }
  .task-status {
    grid-area: status;
    display: flex;
    align-items: center;
    gap: 7px;
  }
  .task-responsibility {
    grid-area: responsibility;
  }
  .task-meta {
    grid-area: meta;
    display: flex;
    gap: 9px;
  }
  .task-chevron {
    grid-area: chevron;
    align-self: center;
  }
}
</style>
