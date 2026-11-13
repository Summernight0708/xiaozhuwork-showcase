<script setup lang="ts">
import { ref } from "vue";
import type { MembershipRow } from "@/types/ui";
import type { TaskListStatusFilter } from "@/domain/task-list";

defineProps<{
  members: readonly MembershipRow[];
  selectionMode: boolean;
}>();

const search = defineModel<string>("search", { required: true });
const status = defineModel<TaskListStatusFilter>("status", { required: true });
const assignee = defineModel<string>("assignee", { required: true });
const mine = defineModel<boolean>("mine", { required: true });
const showMore = ref(false);

const emit = defineEmits<{
  toggleSelectionMode: [];
}>();
</script>

<template>
  <div
    class="task-filters"
    :class="{ 'filters-open': showMore }"
    aria-label="任务筛选"
  >
    <label class="search-field">
      <span class="sr-only">搜索任务</span>
      <input v-model="search" type="search" placeholder="搜索任务" />
    </label>

    <select v-model="status" aria-label="状态筛选">
      <option value="all">全部状态</option>
      <option value="unclaimed">待认领</option>
      <option value="pending_acceptance">待接受</option>
      <option value="not_started">待开始</option>
      <option value="in_progress">进行中</option>
      <option value="waiting_upstream">等待上游</option>
      <option value="blocked">阻塞</option>
      <option value="awaiting_review">待验收</option>
      <option value="completed">已完成</option>
    </select>

    <button
      type="button"
      class="task-more-toggle"
      :aria-expanded="showMore"
      aria-controls="task-extra-filters"
      @click="showMore = !showMore"
    >
      更多筛选{{
        assignee !== "all" || mine || selectionMode ? " · 已启用" : ""
      }}
    </button>
    <div id="task-extra-filters" class="task-extra-filters">
      <select v-model="assignee" aria-label="负责人筛选">
        <option value="all">全部成员</option>
        <option value="unassigned">未分配</option>
        <option
          v-for="member in members"
          :key="member.id"
          :value="member.user_id || ''"
        >
          {{ member.display_name_snapshot || "未命名成员" }}
        </option>
      </select>

      <label class="mine-filter">
        <input v-model="mine" type="checkbox" />
        <span>我的任务</span>
      </label>

      <button
        class="selection-toggle"
        type="button"
        :aria-pressed="selectionMode"
        @click="emit('toggleSelectionMode')"
      >
        {{ selectionMode ? "退出多选" : "多选" }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.task-filters {
  display: grid;
  grid-template-columns: minmax(200px, 1fr) auto auto;
  align-items: center;
  gap: var(--space-sm);
}
.search-field {
  min-width: 0;
}
.search-field input,
.task-filters select {
  width: 100%;
  min-width: 0;
  min-height: 42px;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  padding: 0 var(--space-sm);
  background: var(--tu-surface);
  color: var(--tu-ink);
}
.task-extra-filters {
  display: flex;
  gap: var(--space-sm);
  align-items: center;
}
.task-extra-filters select {
  width: auto;
  min-width: 128px;
}
.mine-filter,
.selection-toggle,
.task-more-toggle {
  display: inline-flex;
  min-height: 42px;
  align-items: center;
  gap: 7px;
  padding: 0 var(--space-sm);
  color: var(--tu-ink);
  background: transparent;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  cursor: pointer;
  white-space: nowrap;
}
.selection-toggle[aria-pressed="true"] {
  border-color: var(--tu-action);
  color: var(--tu-action);
}
.task-more-toggle {
  display: none;
}
@media (max-width: 800px) {
  .task-filters {
    grid-template-columns: minmax(0, 1fr) auto;
  }
  .search-field {
    grid-column: 1 / -1;
  }
  .task-more-toggle {
    display: inline-flex;
  }
  .task-extra-filters {
    display: none;
    grid-column: 1 / -1;
    flex-wrap: wrap;
  }
  .task-filters.filters-open .task-extra-filters {
    display: flex;
  }
  .task-extra-filters select {
    flex: 1 1 150px;
  }
  .mine-filter,
  .selection-toggle {
    flex: 1 1 auto;
    justify-content: center;
  }
}
</style>
