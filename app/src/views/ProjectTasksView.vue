<script setup lang="ts">
import ContextHelpLink from "@/components/help/ContextHelpLink.vue";
defineOptions({ name: "ProjectTasksView" });

import { computed, nextTick, onActivated, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import TaskFilters from "@/components/task/TaskFilters.vue";
import TaskListRow from "@/components/task/TaskListRow.vue";
import TaskMultiSelectBar from "@/components/task/TaskMultiSelectBar.vue";
import UnclaimedTasksSection from "@/components/task/UnclaimedTasksSection.vue";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import {
  isTaskMine,
  isUnclaimedTask,
  matchesTaskListStatus,
  taskListPresentation,
  type TaskListStatusFilter,
  type TaskParticipantSnapshot,
} from "@/domain/task-list";
import { useTaskNavigationStore } from "@/stores/task-navigation";
import type { TaskRow } from "@/types/ui";

const route = useRoute();
const router = useRouter();
const { workspace, projectId, reload } = useWorkspaceRoute();
const navigation = useTaskNavigationStore();

function queryString(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function queryStatus(value: unknown): TaskListStatusFilter {
  const allowed: TaskListStatusFilter[] = [
    "all",
    "unclaimed",
    "pending_acceptance",
    "not_started",
    "in_progress",
    "waiting_upstream",
    "blocked",
    "awaiting_review",
    "completed",
  ];
  const next = queryString(value, "all") as TaskListStatusFilter;
  return allowed.includes(next) ? next : "all";
}

const search = ref(queryString(route.query.q));
const status = ref<TaskListStatusFilter>(queryStatus(route.query.status));
const assignee = ref(queryString(route.query.assignee, "all") || "all");
const mine = ref(route.query.mine === "1");
const selectionMode = ref(false);
const selectedTaskIds = ref<string[]>([]);
const claimingTaskId = ref<string | null>(null);

const participantSnapshots = computed<Record<string, TaskParticipantSnapshot>>(
  () => ({}),
);

function participants(taskId: string): TaskParticipantSnapshot {
  return participantSnapshots.value[taskId] ?? {};
}

const unclaimedCandidates = computed(() =>
  workspace.tasks.filter(isUnclaimedTask).map((task) => ({
    task,
    dependency: workspace.dependencyState(task.id),
  })),
);

const showUnclaimedSpotlight = computed(
  () =>
    status.value === "all" &&
    !search.value.trim() &&
    assignee.value === "all" &&
    !mine.value,
);

const rows = computed(() => {
  const keyword = search.value.trim().toLowerCase();
  return workspace.tasks
    .filter((task) => {
      if (
        keyword &&
        !task.title.toLowerCase().includes(keyword) &&
        !(task.description ?? "").toLowerCase().includes(keyword)
      ) {
        return false;
      }

      const dependency = workspace.dependencyState(task.id);
      if (!matchesTaskListStatus(task, dependency, status.value)) return false;

      if (assignee.value !== "all") {
        if (assignee.value === "unassigned") {
          if (task.assignee_id) return false;
        } else if (task.assignee_id !== assignee.value) {
          return false;
        }
      }

      if (
        mine.value &&
        !isTaskMine(task, workspace.currentUserId, participants(task.id))
      ) {
        return false;
      }
      return true;
    })
    .sort((left, right) => {
      const leftCompleted = left.status === "completed";
      const rightCompleted = right.status === "completed";
      if (leftCompleted !== rightCompleted) return leftCompleted ? 1 : -1;
      return Date.parse(left.deadline_at) - Date.parse(right.deadline_at);
    });
});

const canClaim = computed(
  () => !!workspace.membership && workspace.role !== "observer",
);

function sourceState() {
  return {
    search: search.value,
    status: status.value,
    assignee: assignee.value,
    mine: mine.value,
    selectionMode: selectionMode.value,
  };
}

function rememberAndOpen(task: TaskRow) {
  navigation.rememberSource({
    routeName: "project-tasks",
    projectId: projectId.value,
    taskId: task.id,
    scrollY: window.scrollY,
    state: sourceState(),
  });
  navigation.openDrawer(projectId.value, task.id);
}

function openTask(taskId: string) {
  const task = workspace.findTask(taskId);
  if (task) rememberAndOpen(task);
}

function toggleSelection(taskId: string) {
  if (!selectionMode.value) return;
  selectedTaskIds.value = selectedTaskIds.value.includes(taskId)
    ? selectedTaskIds.value.filter((id) => id !== taskId)
    : [...selectedTaskIds.value, taskId];
}

function toggleSelectionMode() {
  selectionMode.value = !selectionMode.value;
  if (!selectionMode.value) selectedTaskIds.value = [];
}

function cancelSelection() {
  selectionMode.value = false;
  selectedTaskIds.value = [];
}

async function claim(taskId: string) {
  const task = workspace.findTask(taskId);
  if (!task || task.assignee_id || task.assignment_state !== "claimable")
    return;

  claimingTaskId.value = task.id;
  try {
    const result = await workspace.claimTask(task);
    if (!result.ok) {
      showToast(workspace.actionError || "认领失败，请刷新后重试");
      return;
    }
    showToast("任务已认领");
  } catch {
    showToast(workspace.actionError || "认领失败，请重试");
  } finally {
    claimingTaskId.value = null;
  }
}

function viewAllUnclaimed() {
  status.value = "unclaimed";
}

function restoreSourceState() {
  const source = navigation.source;
  if (
    source?.routeName !== "project-tasks" ||
    source.projectId !== projectId.value
  ) {
    return false;
  }

  search.value = String(source.state.search ?? search.value);
  status.value = queryStatus(source.state.status);
  assignee.value = String(source.state.assignee ?? assignee.value);
  mine.value = source.state.mine === true;
  selectionMode.value = source.state.selectionMode === true;
  return true;
}

async function restoreScroll() {
  const source = navigation.source;
  if (
    source?.routeName !== "project-tasks" ||
    source.projectId !== projectId.value
  ) {
    return;
  }
  await nextTick();
  window.scrollTo({ top: source.scrollY, behavior: "auto" });
}

function currentQuery() {
  return {
    ...route.query,
    q: search.value.trim() || undefined,
    status: status.value === "all" ? undefined : status.value,
    assignee: assignee.value === "all" ? undefined : assignee.value,
    mine: mine.value ? "1" : undefined,
  };
}

watch(
  [search, status, assignee, mine],
  () => {
    void router.replace({ query: currentQuery() });
  },
  { flush: "post" },
);

watch(
  () => route.query,
  (query) => {
    const nextSearch = queryString(query.q);
    const nextStatus = queryStatus(query.status);
    const nextAssignee = queryString(query.assignee, "all") || "all";
    const nextMine = query.mine === "1";
    if (search.value !== nextSearch) search.value = nextSearch;
    if (status.value !== nextStatus) status.value = nextStatus;
    if (assignee.value !== nextAssignee) assignee.value = nextAssignee;
    if (mine.value !== nextMine) mine.value = nextMine;
  },
);

onActivated(() => {
  if (restoreSourceState()) void restoreScroll();
});
</script>

<template>
  <div class="xiaozhuwork-page">
    <header class="page-heading">
      <div>
        <div class="page-title-line">
          <h1>任务</h1>
          <ContextHelpLink example-id="dependencies" />
        </div>
      </div>
      <div
        v-if="workspace.capabilities.canCreateTask"
        class="page-heading-actions"
      >
        <RouterLink :to="{ name: 'ai-task-breakdown', params: { projectId } }">
          <van-button plain type="primary">AI 智能拆解</van-button>
        </RouterLink>
        <RouterLink :to="{ name: 'task-create', params: { projectId } }">
          <van-button type="primary">创建任务</van-button>
        </RouterLink>
      </div>
    </header>

    <div class="task-toolbar">
      <TaskFilters
        v-model:search="search"
        v-model:status="status"
        v-model:assignee="assignee"
        v-model:mine="mine"
        :members="workspace.members"
        :selection-mode="selectionMode"
        @toggle-selection-mode="toggleSelectionMode"
      />
    </div>

    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="!workspace.project || !workspace.membership"
      :empty="!workspace.tasks.length"
      empty-title="当前项目还没有任务"
      @retry="reload"
    >
      <UnclaimedTasksSection
        v-if="showUnclaimedSpotlight"
        :candidates="unclaimedCandidates"
        :can-claim="canClaim"
        :claiming-task-id="claimingTaskId"
        @claim="claim"
        @open="openTask"
        @view-all="viewAllUnclaimed"
      />

      <section class="all-tasks">
        <div class="list-heading">
          <div>
            <h2>{{ status === "unclaimed" ? "待认领任务" : "全部任务" }}</h2>
            <span>{{ rows.length }} 项</span>
          </div>
        </div>

        <div v-if="rows.length" class="task-list">
          <TaskListRow
            v-for="task in rows"
            :key="task.id"
            :title="task.title"
            :status="
              taskListPresentation(task, workspace.dependencyState(task.id))
                .status
            "
            :primary-name="workspace.memberName(task.assignee_id)"
            :current-user-is-primary="
              task.assignee_id === workspace.currentUserId
            "
            :current-user-is-collaborator="
              (
                participants(task.id).acceptedCollaboratorUserIds ?? []
              ).includes(workspace.currentUserId || '')
            "
            :collaborator-count="participants(task.id).collaboratorCount ?? 0"
            :weight="task.weight"
            :deadline-at="task.deadline_at"
            :alert="
              taskListPresentation(task, workspace.dependencyState(task.id))
                .alert
            "
            :completed="task.status === 'completed'"
            :selection-mode="selectionMode"
            :selected="selectedTaskIds.includes(task.id)"
            @open="
              selectionMode ? toggleSelection(task.id) : rememberAndOpen(task)
            "
            @toggle-selection="toggleSelection(task.id)"
          />
        </div>

        <div v-else class="surface empty-filter-state">
          <strong>没有符合当前筛选条件的任务</strong>
          <p>调整搜索、状态、负责人或“我的任务”筛选后再看。</p>
        </div>
      </section>

      <TaskMultiSelectBar
        v-if="selectionMode"
        :count="selectedTaskIds.length"
        :can-bulk-update-status="false"
        @cancel="cancelSelection"
      />
    </PageState>
  </div>
</template>

<style scoped>
.task-toolbar {
  margin-bottom: 22px;
}
.all-tasks {
  display: grid;
  gap: 10px;
}
.list-heading {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 16px;
}
.list-heading > div {
  display: flex;
  align-items: baseline;
  gap: 8px;
}
.list-heading h2 {
  margin: 0;
  font-size: 18px;
}
.list-heading span,
.list-heading p {
  color: var(--tu-muted);
  font-size: 13px;
}
.list-heading p {
  margin: 0;
}
.task-list {
  overflow: hidden;
  border-top: 1px solid var(--tu-border);
  border-bottom: 1px solid var(--tu-border);
  background: var(--tu-surface);
}
.empty-filter-state {
  padding: 28px;
  text-align: center;
}
.empty-filter-state p {
  margin: 6px 0 0;
  color: var(--tu-muted);
}
@media (max-width: 760px) {
  .list-heading {
    align-items: start;
    flex-direction: column;
  }
  .page-heading-actions {
    flex-direction: column-reverse;
  }
}

.page-heading-actions {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}
</style>
