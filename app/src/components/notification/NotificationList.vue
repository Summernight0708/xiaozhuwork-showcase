<script setup lang="ts">
import { computed } from "vue";

import NotificationItem from "@/components/notification/NotificationItem.vue";
import type { NotificationRow } from "@/types/ui";

const props = defineProps<{
  items: readonly NotificationRow[];
  projectNames: Readonly<Record<string, string>>;
}>();

const emit = defineEmits<{
  open: [item: NotificationRow];
  dismiss: [item: NotificationRow];
}>();

const groups = computed(() => {
  const result: { label: string; items: NotificationRow[] }[] = [];
  const today = new Date().toDateString();

  for (const item of props.items) {
    const date = new Date(item.created_at);
    const label =
      date.toDateString() === today
        ? "今天"
        : date.toLocaleDateString("zh-CN", { month: "long", day: "numeric" });
    const current = result[result.length - 1];
    if (!current || current.label !== label) {
      result.push({ label, items: [item] });
    } else {
      current.items.push(item);
    }
  }
  return result;
});
</script>

<template>
  <div class="notification-groups">
    <section v-for="group in groups" :key="group.label">
      <h2>{{ group.label }}</h2>
      <div class="surface group-list">
        <NotificationItem
          v-for="item in group.items"
          :key="item.id"
          :item="item"
          :project-name="
            item.project_id ? projectNames[item.project_id] || '项目' : '系统'
          "
          @open="emit('open', item)"
          @dismiss="emit('dismiss', item)"
        />
      </div>
    </section>
  </div>
</template>

<style scoped>
.notification-groups {
  display: grid;
  gap: 20px;
}
.notification-groups section {
  display: grid;
  gap: 8px;
}
.notification-groups h2 {
  margin: 0;
  color: var(--tu-muted);
  font-size: 14px;
  font-weight: 700;
}
.group-list {
  overflow: hidden;
}
</style>
