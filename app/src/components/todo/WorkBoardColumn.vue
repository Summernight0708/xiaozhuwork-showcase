<script setup lang="ts">
import { computed, ref } from "vue";

import WorkTaskCard from "@/components/todo/WorkTaskCard.vue";
import type { WorkBoardColumnId, WorkTaskItem } from "@/domain/todo-workboard";

const props = withDefaults(
  defineProps<{
    id: WorkBoardColumnId;
    label: string;
    items: WorkTaskItem[];
    total?: number;
    showProject?: boolean;
    completed?: boolean;
    historyAvailable?: boolean;
  }>(),
  {
    total: undefined,
    showProject: false,
    completed: false,
    historyAvailable: false,
  },
);

const emit = defineEmits<{
  open: [item: WorkTaskItem];
  "view-history": [];
}>();

const expanded = ref(false);
const mobileVisible = computed(() =>
  expanded.value ? props.items : props.items.slice(0, 3),
);
</script>

<template>
  <section class="work-column" :class="{ 'is-completed': completed }">
    <header>
      <h2>{{ label }}</h2>
      <span>{{ total ?? items.length }}</span>
    </header>
    <div class="task-list desktop-list">
      <WorkTaskCard
        v-for="item in items"
        :key="item.task.id"
        :item="item"
        :show-project="showProject"
        @open="emit('open', $event)"
      />
      <p v-if="!items.length" class="empty">暂无</p>
    </div>
    <div class="task-list mobile-list">
      <WorkTaskCard
        v-for="item in mobileVisible"
        :key="item.task.id"
        :item="item"
        :show-project="showProject"
        @open="emit('open', $event)"
      />
      <p v-if="!items.length" class="empty">暂无</p>
      <button
        v-if="items.length > 3"
        type="button"
        class="expand-button"
        :aria-expanded="expanded"
        @click="expanded = !expanded"
      >
        {{ expanded ? "收起" : `展开另外 ${items.length - 3} 项` }}
      </button>
    </div>
    <button
      v-if="completed && historyAvailable && (total ?? 0) > items.length"
      type="button"
      class="history-link"
      @click="emit('view-history')"
    >
      查看全部 →
    </button>
  </section>
</template>

<style scoped>
.work-column {
  min-width: 0;
  display: grid;
  align-content: start;
  gap: 10px;
  padding: var(--space-sm) 0;
  border-top: 1px solid var(--tu-border);
  background: transparent;
}
.work-column > header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.work-column h2 {
  margin: 0;
  font-size: 15px;
}
.work-column header > span {
  color: var(--tu-muted);
  font-size: 12px;
}
.task-list {
  display: grid;
  gap: 9px;
}
.empty {
  margin: 10px 0;
  color: var(--tu-muted);
  text-align: center;
  font-size: 13px;
}
.mobile-list {
  display: none;
}
.expand-button,
.history-link {
  border: 0;
  background: transparent;
  color: var(--tu-blue-strong);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
  text-decoration: none;
}
.history-link {
  justify-self: end;
}
.is-completed {
  opacity: 0.86;
}
@media (max-width: 767px) {
  .work-column {
    padding: 10px;
  }
  .desktop-list {
    display: none;
  }
  .mobile-list {
    display: grid;
  }
  .is-completed .mobile-list {
    max-height: none;
  }
}
</style>
