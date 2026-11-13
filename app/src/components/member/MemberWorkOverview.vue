<script setup lang="ts">
import { computed, ref } from "vue";

import type { MemberFlowTask } from "@/domain/member-team-work";
import type { MemberWorkSummary } from "@/domain/member-work-facts";

const props = defineProps<{
  summary: MemberWorkSummary;
  primaryTasks: MemberFlowTask[];
  collaboratorTasks: MemberFlowTask[];
}>();

const emit = defineEmits<{
  "open-task": [taskId: string];
}>();

const tab = ref<"primary" | "collaborator">("primary");
const responsibilityTasks = computed(() =>
  tab.value === "primary" ? props.primaryTasks : props.collaboratorTasks,
);
</script>

<template>
  <section class="member-work-overview" aria-label="成员工作详情">
    <header>
      <div>
        <h2>{{ summary.displayName }} · {{ summary.roleLabel }}</h2>
        <p>
          主负责 {{ summary.primaryCount }} · 协作
          {{ summary.collaboratorCount }}
        </p>
      </div>
    </header>

    <div class="responsibility-tabs" role="tablist" aria-label="任务责任">
      <button
        type="button"
        role="tab"
        :aria-selected="tab === 'primary'"
        @click="tab = 'primary'"
      >
        主负责 {{ summary.primaryCount }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="tab === 'collaborator'"
        @click="tab = 'collaborator'"
      >
        协作 {{ summary.collaboratorCount }}
      </button>
    </div>

    <div class="responsibility-list">
      <button
        v-for="task in responsibilityTasks"
        :key="task.id"
        type="button"
        @click="emit('open-task', task.id)"
      >
        <strong>{{ task.title }}</strong>
        <span>{{ tab === "primary" ? task.statusLabel : "协作中" }}</span>
      </button>
      <p v-if="!responsibilityTasks.length" class="empty">
        当前没有{{ tab === "primary" ? "主负责" : "协作" }}任务。
      </p>
    </div>

    <section class="facts" aria-labelledby="member-facts-title">
      <h3 id="member-facts-title">最近工作</h3>
      <button
        v-for="fact in summary.facts.slice(0, 8)"
        :key="fact.id"
        type="button"
        @click="emit('open-task', fact.taskId)"
      >
        <span>{{ fact.text }}</span>
        <time :datetime="fact.occurredAt">{{
          new Date(fact.occurredAt).toLocaleDateString("zh-CN")
        }}</time>
      </button>
      <p v-if="!summary.facts.length" class="empty">暂无正式工作事实。</p>
    </section>
  </section>
</template>

<style scoped>
.member-work-overview {
  display: grid;
  gap: 14px;
}
.member-work-overview header h2,
.member-work-overview header p,
.facts h3 {
  margin: 0;
}
.member-work-overview header p {
  margin-top: 5px;
  color: var(--tu-muted);
  font-size: 12px;
}
.responsibility-tabs {
  display: flex;
  gap: 6px;
}
.responsibility-tabs button {
  min-height: 34px;
  padding: 0 12px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-surface);
  cursor: pointer;
}
.responsibility-tabs button[aria-selected="true"] {
  border-color: var(--tu-blue);
  background: var(--tu-blue-soft);
  color: var(--tu-blue-strong);
  font-weight: 700;
}
.responsibility-list,
.facts {
  display: grid;
  gap: 6px;
}
.responsibility-list > button,
.facts > button {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 9px 10px;
  border: 0;
  border-radius: 8px;
  background: var(--tu-subtle-surface);
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.responsibility-list span,
.facts time,
.empty {
  color: var(--tu-muted);
  font-size: 11px;
}
.facts {
  padding-top: 6px;
  border-top: 1px solid var(--tu-border);
}
.facts h3 {
  font-size: 14px;
}
.empty {
  margin: 8px 0;
}
</style>
