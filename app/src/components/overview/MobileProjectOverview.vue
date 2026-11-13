<script setup lang="ts">
import { ref } from "vue";

import TaskFlowGraph from "@/components/TaskFlowGraph.vue";
import type {
  MobileOverviewTodoItem,
  MobileTaskFlowSummary,
} from "@/domain/mobile-project-overview";
import { projectActionRoute } from "@/domain/project-action-items";
import type { TaskGraphScope } from "@/domain/task-dependency-graph";
import type { TaskDependencyRow, TaskRow } from "@/types/ui";

interface GraphState {
  zoom: number;
  panX: number;
  panY: number;
  scope: TaskGraphScope;
  search: string;
  focusTaskId: string | null;
  historyExpanded: boolean;
}

const props = defineProps<{
  projectId: string;
  archived: boolean;
  projectName: string;
  courseName: string | null;
  deadlineAt: string;
  memberCount: number;
  todoItems: MobileOverviewTodoItem[];
  flowSummary: MobileTaskFlowSummary;
  dueSoonMemberCount: number;
  tasks: TaskRow[];
  dependencies: TaskDependencyRow[];
  memberName: (userId: string | null | undefined) => string;
  currentUserId: string | null;
  initialGraphState: Partial<GraphState>;
}>();

const emit = defineEmits<{
  openTask: [taskId: string];
  graphStateChange: [state: GraphState];
}>();

const flowExpanded = ref(false);

function formatDate(value: string) {
  return new Intl.DateTimeFormat("zh-CN", {
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(value));
}

function todoMeta(item: MobileOverviewTodoItem) {
  const parts = [item.reason];
  if (item.detail) parts.push(item.detail);
  if (item.deadlineAt) parts.push(`DDL ${formatDate(item.deadlineAt)}`);
  return parts.join(" · ");
}

function todoRoute(item: MobileOverviewTodoItem) {
  return (
    projectActionRoute(item.target, props.projectId) ?? {
      name: "project-todos",
      params: { projectId: props.projectId },
    }
  );
}
</script>

<template>
  <div class="mobile-overview">
    <header class="mobile-overview__identity">
      <span class="project-state">{{ archived ? "已归档" : "进行中" }}</span>
      <h1>{{ projectName }}</h1>
      <p>
        {{ courseName || "未设置课程" }}
        <span aria-hidden="true">·</span>
        {{ memberCount }} 位成员
        <span aria-hidden="true">·</span>
        DDL {{ formatDate(deadlineAt) }}
      </p>
    </header>

    <section class="mobile-overview__todos" aria-labelledby="mobile-todo-title">
      <div class="mobile-overview__section-heading">
        <h2 id="mobile-todo-title">我的待办</h2>
        <RouterLink :to="{ name: 'project-todos', params: { projectId } }">
          查看全部我的工作
        </RouterLink>
      </div>

      <div v-if="todoItems.length" class="mobile-overview__todo-list">
        <template v-for="item in todoItems" :key="item.id">
          <button
            v-if="item.target.kind === 'task'"
            type="button"
            class="mobile-overview__todo"
            @click="emit('openTask', item.target.taskId)"
          >
            <strong>{{ item.title }}</strong>
            <span>{{ todoMeta(item) }}</span>
          </button>
          <RouterLink
            v-else
            class="mobile-overview__todo"
            :to="todoRoute(item)"
          >
            <strong>{{ item.title }}</strong>
            <span>{{ todoMeta(item) }}</span>
          </RouterLink>
        </template>
      </div>
      <p v-else class="mobile-overview__empty">
        当前没有需要你立即处理的事项。
      </p>
    </section>

    <section class="mobile-overview__quiet" aria-labelledby="mobile-flow-title">
      <div class="mobile-overview__section-heading">
        <div>
          <h2 id="mobile-flow-title">任务流程</h2>
          <p>
            完成 {{ flowSummary.completed }} / {{ flowSummary.total }} ·
            {{ flowSummary.stages }} 个阶段 · {{ flowSummary.blocked }} 项受阻
          </p>
        </div>
        <button
          type="button"
          class="mobile-overview__toggle"
          aria-controls="mobile-task-flow"
          :aria-expanded="flowExpanded"
          @click="flowExpanded = !flowExpanded"
        >
          {{ flowExpanded ? "收起任务流程" : "展开任务流程" }}
        </button>
      </div>

      <div
        v-if="flowExpanded"
        id="mobile-task-flow"
        class="mobile-overview__flow-window"
        role="region"
        aria-label="任务流程详情"
        tabindex="0"
      >
        <TaskFlowGraph
          :tasks="tasks"
          :dependencies="dependencies"
          :member-name="memberName"
          :current-user-id="currentUserId"
          :initial-state="initialGraphState"
          @state-change="emit('graphStateChange', $event)"
          @open-task="emit('openTask', $event)"
        />
      </div>
    </section>

    <section
      class="mobile-overview__quiet"
      aria-labelledby="mobile-member-title"
    >
      <div class="mobile-overview__section-heading">
        <div>
          <h2 id="mobile-member-title">成员工作</h2>
          <p>
            {{ memberCount }} 位成员 · {{ dueSoonMemberCount }} 人有临期任务
          </p>
        </div>
        <RouterLink :to="{ name: 'project-members', params: { projectId } }">
          查看成员工作
        </RouterLink>
      </div>
    </section>
  </div>
</template>

<style scoped>
.mobile-overview {
  min-width: 0;
  display: grid;
  gap: 22px;
}

.mobile-overview__identity {
  min-width: 0;
  padding: 2px 0 4px;
}

.mobile-overview__identity h1 {
  margin: 5px 0;
  overflow-wrap: anywhere;
  color: var(--tu-ink);
  font-size: clamp(25px, 8vw, 32px);
  line-height: 1.12;
  letter-spacing: -0.035em;
}

.mobile-overview__identity p {
  margin: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  color: var(--tu-muted);
  font-size: 13px;
  line-height: 1.5;
}

.project-state {
  color: var(--tu-muted);
  font-size: 12px;
  font-weight: 700;
}

.mobile-overview__todos {
  min-width: 0;
  padding: 15px;
  border: 1px solid var(--tu-border);
  border-radius: 13px;
  background: var(--tu-surface);
}

.mobile-overview__quiet {
  min-width: 0;
  padding-top: 2px;
  border-top: 1px solid var(--tu-border);
}

.mobile-overview__section-heading {
  min-width: 0;
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: 12px;
}

.mobile-overview__section-heading > div {
  min-width: 0;
}

.mobile-overview__section-heading h2 {
  margin: 0;
  color: var(--tu-ink);
  font-size: 17px;
  letter-spacing: -0.02em;
}

.mobile-overview__section-heading p {
  margin: 4px 0 0;
  color: var(--tu-muted);
  font-size: 12px;
  line-height: 1.5;
}

.mobile-overview__section-heading a,
.mobile-overview__toggle {
  flex: 0 0 auto;
  min-height: 36px;
  display: inline-flex;
  align-items: center;
  padding: 0;
  border: 0;
  background: transparent;
  color: #675846;
  font: inherit;
  font-size: 12px;
  font-weight: 700;
  cursor: pointer;
}

.mobile-overview__section-heading a:hover,
.mobile-overview__section-heading a:focus-visible,
.mobile-overview__toggle:hover,
.mobile-overview__toggle:focus-visible {
  color: var(--tu-ink);
  text-decoration: underline;
  text-underline-offset: 3px;
}

.mobile-overview__todo-list {
  display: grid;
  margin-top: 10px;
}

.mobile-overview__todo {
  min-width: 0;
  width: 100%;
  display: grid;
  gap: 4px;
  padding: 11px 0;
  border: 0;
  border-top: 1px solid var(--tu-border);
  background: transparent;
  color: var(--tu-ink);
  text-align: left;
  text-decoration: none;
  cursor: pointer;
}

.mobile-overview__todo:first-child {
  border-top: 0;
}

.mobile-overview__todo strong {
  min-width: 0;
  overflow: hidden;
  font-size: 14px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mobile-overview__todo span {
  color: var(--tu-muted);
  font-size: 12px;
  line-height: 1.45;
  overflow-wrap: anywhere;
}

.mobile-overview__todo:hover strong,
.mobile-overview__todo:focus-visible strong {
  text-decoration: underline;
  text-underline-offset: 3px;
}

.mobile-overview__todo:focus-visible,
.mobile-overview__toggle:focus-visible,
.mobile-overview__section-heading a:focus-visible {
  outline: 2px solid currentcolor;
  outline-offset: 3px;
}

.mobile-overview__empty {
  margin: 12px 0 0;
  color: var(--tu-muted);
  font-size: 12px;
  line-height: 1.55;
}

.mobile-overview__flow-window {
  min-width: 0;
  width: 100%;
  max-width: 100%;
  max-height: min(56vh, 460px);
  margin-top: 10px;
  overflow-x: hidden;
  overflow-y: auto;
  overscroll-behavior: contain;
  border-radius: 14px;
}

.mobile-overview__flow-window :deep(.task-flow),
.mobile-overview__flow-window :deep(.task-flow__toolbar),
.mobile-overview__flow-window :deep(.task-flow__compact),
.mobile-overview__flow-window :deep(.task-flow__compact-stage),
.mobile-overview__flow-window :deep(.task-flow__compact-node) {
  min-width: 0;
  max-width: 100%;
}

.mobile-overview__flow-window :deep(.task-flow__toolbar) {
  grid-template-columns: minmax(0, 1fr);
}

.mobile-overview__flow-window :deep(.task-flow__scope) {
  min-width: 0;
  flex-wrap: wrap;
}

.mobile-overview__flow-window :deep(.task-flow__search) {
  min-width: 0;
  width: 100%;
  grid-column: 1;
  grid-row: auto;
}

.mobile-overview__flow-window :deep(select),
.mobile-overview__flow-window :deep(input) {
  max-width: 100%;
}

html[data-theme="dark"] .mobile-overview__section-heading a,
html[data-theme="dark"] .mobile-overview__toggle {
  color: #c6b8a7;
}
</style>
