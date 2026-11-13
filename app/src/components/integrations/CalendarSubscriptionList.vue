<script setup lang="ts">
import { computed } from "vue";
import type { CalendarSubscription } from "@/services/calendar-subscriptions";

const props = defineProps<{
  items: CalendarSubscription[];
  pendingId: string | null;
  canRevoke: boolean;
}>();
const emit = defineEmits<{ revoke: [subscription: CalendarSubscription] }>();
const ordered = computed(() =>
  [...props.items].sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
);
function status(item: CalendarSubscription): string {
  if (item.revokedAt) return "已撤销";
  if (new Date(item.expiresAt).getTime() <= Date.now()) return "已过期";
  return "有效";
}
</script>

<template>
  <section class="calendar-list">
    <h3>已签发的订阅</h3>
    <p v-if="ordered.length === 0">暂无订阅。</p>
    <ul v-else>
      <li v-for="item in ordered" :key="item.id" class="calendar-item">
        <div>
          <strong>{{ status(item) }}</strong>
          <p>创建：{{ new Date(item.createdAt).toLocaleString() }}</p>
          <p>到期：{{ new Date(item.expiresAt).toLocaleString() }}</p>
          <p>任务标题：{{ item.showTitles ? "显示" : "隐藏" }}</p>
        </div>
        <button
          v-if="!item.revokedAt && canRevoke"
          type="button"
          :disabled="pendingId !== null"
          @click="emit('revoke', item)"
        >
          {{ pendingId === item.id ? "撤销中…" : "撤销订阅" }}
        </button>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.calendar-list h3 {
  margin-bottom: 0.7rem;
}
.calendar-list ul {
  list-style: none;
  margin: 0;
  padding: 0;
}
.calendar-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
  border-bottom: 1px solid var(--tu-border);
  padding: 1rem 0;
}
.calendar-item p {
  margin: 0.2rem 0;
  font-size: 0.9rem;
}
button {
  background: transparent;
  color: var(--tu-danger);
  border: 1px solid currentColor;
  border-radius: 8px;
  padding: 0.5rem 0.8rem;
}
button:disabled {
  opacity: 0.5;
}
@media (max-width: 640px) {
  .calendar-item {
    flex-direction: column;
    align-items: flex-start;
  }
}
</style>
