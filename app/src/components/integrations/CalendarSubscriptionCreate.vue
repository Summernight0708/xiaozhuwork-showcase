<script setup lang="ts">
import { ref } from "vue";

defineProps<{ disabled: boolean; pending: boolean }>();
const emit = defineEmits<{ create: [showTitles: boolean] }>();
const showTitles = ref(false);
</script>

<template>
  <section class="calendar-create">
    <h3>创建只读日历订阅</h3>
    <label class="calendar-option">
      <input
        v-model="showTitles"
        type="checkbox"
        :disabled="disabled || pending"
      />
      在外部日历显示真实任务标题
    </label>
    <p v-if="showTitles" class="calendar-warning" role="status">
      外部日历服务可能缓存任务标题，即使订阅已撤销也不能保证删除旧数据。
    </p>
    <p v-else class="calendar-note">
      默认仅显示“小猪作业任务截止”，不会公开任务标题。
    </p>
    <button
      type="button"
      :disabled="disabled || pending"
      @click="emit('create', showTitles)"
    >
      {{ pending ? "创建中…" : "创建订阅链接" }}
    </button>
  </section>
</template>

<style scoped>
.calendar-create {
  display: grid;
  gap: 0.75rem;
  padding: 1rem 0;
}
.calendar-create h3,
.calendar-create p {
  margin: 0;
}
.calendar-option {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.calendar-warning {
  color: var(--tu-warning-ink);
}
.calendar-note {
  color: var(--tu-muted);
}
button {
  width: fit-content;
  padding: 0.6rem 1rem;
  background: var(--tu-action);
  color: var(--tu-action-contrast);
  border: 0;
  border-radius: 8px;
}
button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
