<script setup lang="ts">
import { computed } from "vue";

import type { NotificationRow } from "@/types/ui";

const props = defineProps<{
  item: NotificationRow;
  projectName: string;
}>();

const emit = defineEmits<{ open: []; dismiss: [] }>();

const timeLabel = computed(() =>
  new Date(props.item.created_at).toLocaleString("zh-CN", {
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }),
);
</script>

<template>
  <div class="notification-item" :class="{ unread: !item.read_at }">
    <button class="notification-open" type="button" @click="emit('open')">
      <span class="unread-marker" aria-hidden="true" />
      <span class="notification-copy">
        <span class="title-line">
          <strong>{{ item.title }}</strong>
          <span v-if="!item.read_at" class="unread-label">未读</span>
        </span>
        <span class="context">{{ item.message }}</span>
        <span class="meta">{{ projectName }} · {{ timeLabel }}</span>
      </span>
      <span class="chevron" aria-hidden="true">›</span>
    </button>
    <button
      class="notification-dismiss"
      type="button"
      aria-label="删除通知"
      title="删除通知"
      @click="emit('dismiss')"
    >
      ×
    </button>
  </div>
</template>

<style scoped>
.notification-item {
  width: 100%;
  min-height: 88px;
  padding: 0;
  border: 0;
  border-bottom: 1px solid var(--tu-border);
  background: var(--tu-surface);
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.notification-open {
  width: 100%;
  min-height: 86px;
  display: grid;
  grid-template-columns: 8px minmax(0, 1fr) auto;
  gap: 10px;
  align-items: start;
  text-align: left;
  cursor: pointer;
  border: 0;
  color: var(--tu-ink);
  background: transparent;
  padding: 15px 56px 15px 16px;
}
.notification-item {
  position: relative;
}
.notification-dismiss {
  position: absolute;
  right: 8px;
  top: 12px;
  min-width: 40px;
  min-height: 40px;
  border: 0;
  background: transparent;
  color: var(--tu-muted);
  font-size: 24px;
  cursor: pointer;
}
.notification-dismiss:hover {
  background: var(--tu-subtle-surface);
  color: var(--tu-danger);
}
.notification-item:last-child {
  border-bottom: 0;
}
.notification-open:hover {
  background: color-mix(in srgb, var(--tu-blue-soft) 40%, transparent);
}
.unread-marker {
  width: 7px;
  height: 7px;
  margin-top: 7px;
  border-radius: 50%;
  background: transparent;
}
.unread .unread-marker {
  background: var(--tu-blue);
}
.notification-copy,
.title-line {
  min-width: 0;
  display: grid;
  gap: 5px;
}
.title-line {
  grid-template-columns: minmax(0, 1fr) auto;
}
.title-line strong {
  overflow: hidden;
  text-overflow: ellipsis;
}
.unread-label {
  align-self: start;
  padding: 2px 6px;
  border-radius: var(--radius-control);
  background: var(--tu-blue-soft);
  color: var(--tu-blue-strong);
  font-size: 11px;
  font-weight: 700;
}
.context,
.meta {
  color: var(--tu-muted);
  font-size: 13px;
  line-height: 1.45;
}
.context {
  white-space: pre-line;
  overflow-wrap: anywhere;
}
.meta {
  font-size: 12px;
}
.chevron {
  align-self: center;
  color: var(--tu-muted);
  font-size: 24px;
}
</style>
