<script setup lang="ts">
import { computed } from "vue";
import { displayStatusLabel } from "@/domain/presentation-labels";

const props = defineProps<{ status: string }>();

const tone = computed(() => {
  if (["blocked", "rejected", "request_changes"].includes(props.status))
    return "danger";
  if (
    ["completed", "completed_without_review", "approved", "formal"].includes(
      props.status,
    )
  )
    return "success";
  if (
    [
      "not_started",
      "waiting_upstream",
      "awaiting_review",
      "pending_acceptance",
      "pending",
    ].includes(props.status)
  )
    return "warning";
  return "info";
});
</script>

<template>
  <span class="status-badge" :data-tone="tone">{{
    displayStatusLabel(status)
  }}</span>
</template>

<style scoped>
.status-badge {
  display: inline-flex;
  align-items: center;
  min-height: 24px;
  padding: 3px 7px;
  border-radius: var(--radius-control);
  font-size: 12px;
  font-weight: 600;
  background: var(--tu-blue-soft);
  color: var(--tu-blue-strong);
}
.status-badge[data-tone="success"] {
  background: var(--tu-success-surface);
  color: var(--tu-success-ink);
}
.status-badge[data-tone="warning"] {
  background: var(--tu-warning-surface);
  color: var(--tu-warning-ink);
}
.status-badge[data-tone="danger"] {
  background: var(--tu-danger-surface);
  color: var(--tu-danger-ink);
}
</style>
