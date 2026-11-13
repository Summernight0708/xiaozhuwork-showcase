<script setup lang="ts">
import { computed } from "vue";

import type { UnclaimedTaskCandidate } from "@/domain/task-list";
import { topUnclaimedTasks } from "@/domain/task-list";

const props = withDefaults(
  defineProps<{
    candidates: readonly UnclaimedTaskCandidate[];
    canClaim: boolean;
    claimingTaskId?: string | null;
    maxVisible?: number;
  }>(),
  { claimingTaskId: null, maxVisible: 5 },
);

const emit = defineEmits<{
  claim: [taskId: string];
  open: [taskId: string];
  viewAll: [];
}>();

const visible = computed(() =>
  topUnclaimedTasks(props.candidates, props.maxVisible),
);

function stars(weight: number | null) {
  return Math.max(1, Math.min(5, Math.round(weight || 1)));
}

function ddl(deadlineAt: string) {
  return new Date(deadlineAt).toLocaleDateString("zh-CN", {
    month: "numeric",
    day: "numeric",
  });
}
</script>

<template>
  <section v-if="candidates.length" class="unclaimed-section">
    <div class="section-heading">
      <div>
        <h2>
          待认领 <span>{{ candidates.length }}</span>
        </h2>
        <p>优先展示已逾期、即将到期的任务；星级表示任务难度 / 贡献权重。</p>
      </div>
      <button
        v-if="candidates.length > visible.length"
        type="button"
        class="view-all"
        @click="emit('viewAll')"
      >
        查看全部 {{ candidates.length }} 个
      </button>
    </div>

    <div class="unclaimed-grid">
      <article v-for="{ task, dependency } in visible" :key="task.id">
        <button
          class="unclaimed-main"
          type="button"
          @click="emit('open', task.id)"
        >
          <strong>{{ task.title }}</strong>
          <span
            class="stars"
            role="img"
            :aria-label="`任务难度 ${stars(task.weight)}/5`"
            >{{ "★".repeat(stars(task.weight))
            }}{{ "☆".repeat(5 - stars(task.weight)) }}</span
          >
          <span>DDL {{ ddl(task.deadline_at) }}</span>
          <span :class="{ waiting: dependency.blocked }">
            {{
              dependency.blocked
                ? `等待上游：${dependency.incompleteUpstreamCount} 项未完成`
                : "可立即开始"
            }}
          </span>
        </button>
        <button
          v-if="canClaim && !task.assignee_id"
          class="claim-button"
          type="button"
          :aria-label="`认领任务：${task.title}`"
          :disabled="claimingTaskId === task.id"
          @click="emit('claim', task.id)"
        >
          {{ claimingTaskId === task.id ? "认领中…" : "认领" }}
        </button>
      </article>
    </div>
  </section>
</template>

<style scoped>
.unclaimed-section {
  margin-bottom: 24px;
}
.section-heading {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 18px;
  margin-bottom: 10px;
}
.section-heading h2 {
  margin: 0;
  font-size: 18px;
}
.section-heading h2 span {
  color: var(--tu-muted);
  font-weight: 600;
}
.section-heading p {
  margin: 5px 0 0;
  color: var(--tu-muted);
  font-size: 13px;
}
.view-all {
  border: 0;
  background: transparent;
  color: var(--tu-blue-strong);
  cursor: pointer;
}
.unclaimed-grid {
  display: grid;
  border-top: 1px solid var(--tu-border);
  border-bottom: 1px solid var(--tu-border);
}
.unclaimed-grid article {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-sm) var(--space-xs);
  border-bottom: 1px solid var(--tu-border);
  background: var(--tu-surface);
}
.unclaimed-grid article:last-child {
  border-bottom: 0;
}
.unclaimed-main {
  min-width: 0;
  display: grid;
  justify-items: start;
  gap: 4px;
  border: 0;
  padding: 0;
  background: transparent;
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.unclaimed-main strong {
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.unclaimed-main span {
  color: var(--tu-muted);
  font-size: 12px;
}
.unclaimed-main .stars {
  color: var(--tu-star);
}
.unclaimed-main .waiting {
  color: var(--tu-warning);
}
.claim-button {
  min-height: 44px;
  padding: 0 13px;
  border: 1px solid var(--tu-action);
  border-radius: var(--radius-control);
  background: var(--tu-action);
  color: var(--tu-action-contrast);
  cursor: pointer;
}
@media (hover: hover) {
  .claim-button:not(:disabled):hover {
    border-color: var(--tu-action-hover);
    background: var(--tu-action-hover);
  }
}
.claim-button:not(:disabled):active {
  border-color: var(--tu-action-active);
  background: var(--tu-action-active);
}
.claim-button:disabled {
  cursor: wait;
  opacity: 0.6;
}
@media (max-width: 600px) {
  .section-heading {
    align-items: start;
    flex-direction: column;
  }
}
</style>
