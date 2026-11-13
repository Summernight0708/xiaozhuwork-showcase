<script setup lang="ts">
import { ref, watch } from "vue";

const props = withDefaults(
  defineProps<{
    title: string;
    defaultOpen?: boolean;
    badge?: number | string | null;
  }>(),
  { defaultOpen: false, badge: null },
);

const open = ref(props.defaultOpen);

watch(
  () => props.defaultOpen,
  (value) => {
    open.value = value;
  },
);
</script>

<template>
  <section class="task-detail-section">
    <button
      type="button"
      class="section-toggle"
      :aria-expanded="open"
      @click="open = !open"
    >
      <span>{{ title }}</span>
      <span class="toggle-meta">
        <span v-if="badge !== null && badge !== undefined" class="count-badge">
          {{ badge }}
        </span>
        <span aria-hidden="true">{{ open ? "▾" : "▸" }}</span>
      </span>
    </button>
    <div v-show="open" class="section-body">
      <slot />
    </div>
  </section>
</template>

<style scoped>
.task-detail-section {
  min-width: 0;
  border-top: 1px solid var(--tu-border);
}
.section-toggle {
  width: 100%;
  min-height: 52px;
  display: flex;
  justify-content: space-between;
  gap: 14px;
  align-items: center;
  padding: 0 var(--space-xs);
  border: 0;
  background: transparent;
  color: var(--tu-ink);
  cursor: pointer;
  font: inherit;
  font-weight: 800;
  text-align: left;
}
.toggle-meta {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: var(--tu-muted);
}
.count-badge {
  min-width: 22px;
  padding: 2px 7px;
  color: var(--tu-blue-strong);
  font-size: 12px;
  text-align: center;
}
.section-body {
  padding: 0 var(--space-xs) var(--space-lg);
}
</style>
