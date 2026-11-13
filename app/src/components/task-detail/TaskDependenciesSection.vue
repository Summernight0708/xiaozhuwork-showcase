<script setup lang="ts">
import { displayStatusLabel } from "@/domain/presentation-labels";
import type { TaskRow } from "@/types/ui";

defineProps<{
  upstreamTasks: readonly TaskRow[];
  downstreamTasks: readonly TaskRow[];
  blocked?: boolean;
  incompleteUpstreamCount?: number;
  canEdit?: boolean;
}>();

const emit = defineEmits<{
  edit: [];
}>();
</script>

<template>
  <div class="dependencies">
    <div class="dependency-heading">
      <strong>直接上下游</strong>
      <button
        v-if="canEdit"
        type="button"
        class="plain-action"
        @click="emit('edit')"
      >
        编辑
      </button>
    </div>
    <p v-if="blocked" class="capability-note">
      当前有
      {{ incompleteUpstreamCount ?? 0 }}
      个上游任务尚未完成，但不妨碍你提前提交成果。
    </p>
    <div class="dependency-grid">
      <div>
        <strong>上游任务</strong>
        <ul v-if="upstreamTasks.length">
          <li v-for="upstream in upstreamTasks" :key="upstream.id">
            {{ upstream.title }} · {{ displayStatusLabel(upstream.status) }}
            <span v-if="upstream.status !== 'completed' && blocked">
              · 等待上游</span
            >
            <span v-else-if="upstream.status !== 'completed'">
              · 尚未完成（不阻碍提交）</span
            >
            <span v-else> · 已完成</span>
          </li>
        </ul>
        <p v-else class="muted">无直接上游任务。</p>
      </div>
      <div>
        <strong>下游任务</strong>
        <ul v-if="downstreamTasks.length">
          <li v-for="downstream in downstreamTasks" :key="downstream.id">
            {{ downstream.title }} · {{ displayStatusLabel(downstream.status) }}
          </li>
        </ul>
        <p v-else class="muted">无直接下游任务。</p>
      </div>
    </div>
    <slot />
  </div>
</template>

<style scoped>
.dependencies {
  display: grid;
  gap: 14px;
  padding-top: 16px;
}
.dependency-heading {
  display: flex;
  justify-content: space-between;
  gap: 12px;
}
.dependency-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}
.dependency-grid > div {
  min-width: 0;
  padding: var(--space-sm) 0;
  border-top: 1px solid var(--tu-border);
}
.dependency-grid ul {
  margin: 7px 0 0;
  padding-left: 18px;
}
.muted {
  color: var(--tu-muted);
}
.plain-action {
  border: 0;
  background: transparent;
  color: var(--tu-blue-strong);
  cursor: pointer;
  font-weight: 700;
}
@media (max-width: 640px) {
  .dependency-grid {
    grid-template-columns: 1fr;
  }
}
</style>
