<script setup lang="ts">
import { computed } from "vue";

const props = defineProps<{
  value?: number | null;
}>();

const normalized = computed(() => {
  const rounded = Math.round(props.value ?? 1);
  return Math.min(5, Math.max(1, rounded));
});

const stars = computed(
  () => "★".repeat(normalized.value) + "☆".repeat(5 - normalized.value),
);
</script>

<template>
  <span
    class="task-stars"
    role="img"
    :aria-label="`任务难度 ${normalized}/5`"
    >{{ stars }}</span
  >
</template>

<style scoped>
.task-stars {
  color: var(--tu-star);
  letter-spacing: 1px;
  white-space: nowrap;
}
</style>
