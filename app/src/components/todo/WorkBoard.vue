<script setup lang="ts">
import WorkBoardColumn from "@/components/todo/WorkBoardColumn.vue";
import {
  WORK_BOARD_COLUMNS,
  type WorkBoardModel,
  type WorkTaskItem,
} from "@/domain/todo-workboard";

withDefaults(
  defineProps<{
    model: WorkBoardModel;
    showProject?: boolean;
    completedHistoryAvailable?: boolean;
  }>(),
  { showProject: false, completedHistoryAvailable: false },
);

const emit = defineEmits<{
  open: [item: WorkTaskItem];
  "view-completed-history": [];
}>();
</script>

<template>
  <div class="work-board" aria-label="我的任务">
    <WorkBoardColumn
      v-for="column in WORK_BOARD_COLUMNS"
      :id="column.id"
      :key="column.id"
      :label="column.label"
      :items="model.columns[column.id]"
      :total="column.id === 'completed' ? model.completedTotal : undefined"
      :completed="column.id === 'completed'"
      :show-project="showProject"
      :history-available="
        column.id === 'completed' && completedHistoryAvailable
      "
      @open="emit('open', $event)"
      @view-history="emit('view-completed-history')"
    />
  </div>
</template>

<style scoped>
.work-board {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
  align-items: start;
}
@media (max-width: 1100px) and (min-width: 768px) {
  .work-board {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
@media (max-width: 767px) {
  .work-board {
    grid-template-columns: 1fr;
  }
}
</style>
