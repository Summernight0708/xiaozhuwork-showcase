<script setup lang="ts">
export interface ActionRequiredItem {
  id: string;
  projectName?: string;
  title: string;
  detail?: string;
  kindLabel: string;
}

defineProps<{
  items: ActionRequiredItem[];
}>();

const emit = defineEmits<{
  open: [id: string];
}>();
</script>

<template>
  <section
    class="surface action-required"
    aria-labelledby="action-required-title"
  >
    <header>
      <h2 id="action-required-title">需要响应</h2>
      <span>{{ items.length }}</span>
    </header>
    <div v-if="items.length" class="action-grid">
      <button
        v-for="item in items"
        :key="item.id"
        type="button"
        class="action-card"
        @click="emit('open', item.id)"
      >
        <span class="kind">{{ item.kindLabel }}</span>
        <strong>{{ item.title }}</strong>
        <small v-if="item.projectName">{{ item.projectName }}</small>
        <small v-if="item.detail">{{ item.detail }}</small>
      </button>
    </div>
    <p v-else class="empty">当前没有需要你确认或决策的事项。</p>
  </section>
</template>

<style scoped>
.action-required {
  padding: 18px;
}
.action-required > header {
  display: flex;
  align-items: center;
  gap: 9px;
  margin-bottom: 12px;
}
.action-required h2 {
  margin: 0;
  font-size: 17px;
}
.action-required header span {
  min-width: 24px;
  height: 24px;
  display: inline-grid;
  place-items: center;
  border-radius: 999px;
  background: var(--tu-blue-soft);
  color: var(--tu-blue-strong);
  font-size: 12px;
  font-weight: 800;
}
.action-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
}
.action-card {
  min-width: 0;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  align-items: baseline;
  gap: 4px 9px;
  padding: 10px 12px;
  border: 1px solid var(--tu-border);
  border-radius: 10px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.action-card:hover,
.action-card:focus-visible {
  border-color: var(--tu-blue);
  outline: none;
}
.kind {
  color: var(--tu-blue-strong);
  font-size: 11px;
  font-weight: 800;
}
.action-card strong {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.action-card small {
  grid-column: 2;
  color: var(--tu-muted);
  font-size: 11px;
}
.empty {
  margin: 0;
  color: var(--tu-muted);
  font-size: 13px;
}
@media (max-width: 700px) {
  .action-grid {
    grid-template-columns: 1fr;
  }
}
</style>
