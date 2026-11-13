<script setup lang="ts">
defineOptions({ name: "ProjectTodosView" });

import { computed, onActivated } from "vue";
import { useRouter } from "vue-router";

import PageState from "@/components/common/PageState.vue";
import ActionRequiredSection from "@/components/todo/ActionRequiredSection.vue";
import WorkBoard from "@/components/todo/WorkBoard.vue";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import {
  buildProjectActionItems,
  projectActionRoute,
} from "@/domain/project-action-items";
import {
  buildProjectWorkInputs,
  buildWorkBoard,
  type WorkTaskItem,
} from "@/domain/todo-workboard";
import { useTaskNavigationStore } from "@/stores/task-navigation";
import type { TaskRow } from "@/types/ui";

const router = useRouter();
const { workspace, projectId, reload } = useWorkspaceRoute();
const navigation = useTaskNavigationStore();

const boardInputs = computed(() =>
  buildProjectWorkInputs({
    tasks: workspace.tasks,
    reviews: workspace.reviews,
    projectId: projectId.value,
    projectName: workspace.project?.name ?? "",
    currentUserId: workspace.currentUserId,
    isAcceptedCollaborator: (taskId) =>
      workspace.isAcceptedCollaborator?.(taskId) ?? false,
    taskResponsibilityKind: (task) =>
      workspace.taskResponsibilityKind?.(task) ?? null,
    collaboratorsForTask: (taskId) =>
      workspace.collaboratorsForTask?.(taskId) ?? [],
    dependencyState: (taskId) =>
      workspace.dependencyState?.(taskId) ?? { blocked: false },
    upstreamTasks: (taskId) => workspace.upstreamTasks?.(taskId) ?? [],
  }),
);

const board = computed(() => buildWorkBoard(boardInputs.value));

const actions = computed(() =>
  buildProjectActionItems({
    projectId: projectId.value,
    currentUserId: workspace.currentUserId,
    role: workspace.role,
    capabilities: workspace.capabilities,
    tasks: workspace.tasks,
    assignmentOffers: workspace.assignmentOffers ?? [],
    reviews: workspace.reviews,
    joinRequests: workspace.joinRequests ?? [],
    contributionReport: workspace.contributionReport,
    contributionConfirmations: workspace.contributionConfirmations ?? [],
    findCollaborator: (taskId) => workspace.findCollaborator?.(taskId),
  }),
);

const empty = computed(
  () =>
    !actions.value.length &&
    Object.values(board.value.columns).every((items) => !items.length),
);

function openTask(task: TaskRow) {
  navigation.rememberSource({
    routeName: "project-todos",
    projectId: projectId.value,
    taskId: task.id,
    scrollY: window.scrollY,
    state: { scope: "project" },
  });
  navigation.openDrawer(projectId.value, task.id);
}

function openBoardTask(item: WorkTaskItem) {
  openTask(item.task);
}

async function viewCompletedHistory() {
  await router.push({
    name: "project-tasks",
    params: { projectId: projectId.value },
  });
}

async function openAction(id: string) {
  const action = actions.value.find((item) => item.id === id);
  if (!action) return;
  if (action.target.kind === "task") {
    const task = workspace.findTask(action.target.taskId);
    if (task) openTask(task);
    return;
  }
  const route = projectActionRoute(action.target, projectId.value);
  if (route) await router.push(route);
}

async function ensureAuxiliary() {
  await Promise.all([
    workspace.loadReviews(),
    workspace.capabilities.canReviewJoinRequest
      ? workspace.loadInvitations()
      : Promise.resolve(),
    workspace.capabilities.canConfirmContributionReport
      ? workspace.loadContributionReport()
      : Promise.resolve(),
  ]);
}

onActivated(() => void ensureAuxiliary());
void ensureAuxiliary();
</script>

<template>
  <div class="xiaozhuwork-page project-work-page">
    <header class="page-heading">
      <div>
        <h1>我的工作</h1>
      </div>
    </header>

    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="!workspace.project || !workspace.membership"
      :empty="empty"
      empty-title="当前项目没有待处理工作"
      @retry="reload"
    >
      <div class="project-work-content">
        <ActionRequiredSection :items="actions" @open="openAction" />
        <section aria-labelledby="project-my-tasks-title">
          <h2 id="project-my-tasks-title" class="section-title">我的任务</h2>
          <WorkBoard
            :model="board"
            completed-history-available
            @open="openBoardTask"
            @view-completed-history="viewCompletedHistory"
          />
        </section>
      </div>
    </PageState>
  </div>
</template>

<style scoped>
.project-work-page,
.project-work-content {
  display: grid;
  gap: 18px;
}
.section-title {
  margin: 0 0 10px;
  font-size: 17px;
}
</style>
