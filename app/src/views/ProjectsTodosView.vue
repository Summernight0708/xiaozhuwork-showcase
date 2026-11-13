<script setup lang="ts">
defineOptions({ name: "ProjectsTodosView" });

import { computed, onActivated, onMounted, ref } from "vue";
import { useRouter, type RouteLocationRaw } from "vue-router";

import ActionRequiredSection from "@/components/todo/ActionRequiredSection.vue";
import WorkBoard from "@/components/todo/WorkBoard.vue";
import PageState from "@/components/common/PageState.vue";
import { canReviewTaskSubmission } from "@/domain/task-review";
import {
  buildWorkBoard,
  type WorkTaskInput,
  type WorkTaskItem,
} from "@/domain/todo-workboard";
import { getBackend } from "@/services/backend";
import { createRepository } from "@/services/repository";
import { useAuthStore } from "@/stores/auth";
import { useProjectsStore } from "@/stores/projects";
import { useTaskNavigationStore } from "@/stores/task-navigation";
import type { ReviewRoundRow, TaskDependencyRow, TaskRow } from "@/types/ui";

type ActionItem = {
  id: string;
  projectId: string;
  projectName: string;
  title: string;
  detail?: string;
  kindLabel: string;
  task?: TaskRow;
  route?: RouteLocationRaw;
};

const router = useRouter();
const auth = useAuthStore();
const projects = useProjectsStore();
const navigation = useTaskNavigationStore();
const loading = ref(false);
const error = ref<string | null>(null);
const actions = ref<ActionItem[]>([]);
const boardInputs = ref<WorkTaskInput[]>([]);
const projectFilter = ref("all");

function latestReview(taskId: string, reviews: ReviewRoundRow[]) {
  return reviews
    .filter((round) => round.task_id === taskId)
    .sort((left, right) => right.round_number - left.round_number)[0];
}

function dependencyInfo(
  task: TaskRow,
  tasks: TaskRow[],
  dependencies: TaskDependencyRow[],
) {
  const upstreamIds = dependencies
    .filter((dependency) => dependency.downstream_task_id === task.id)
    .map((dependency) => dependency.upstream_task_id);
  const upstreamTasks = upstreamIds
    .map((id) => tasks.find((candidate) => candidate.id === id))
    .filter((candidate): candidate is TaskRow => !!candidate);
  const incomplete = upstreamTasks.filter(
    (candidate) => candidate.status !== "completed",
  );
  return {
    blocked: incomplete.length > 0,
    upstreamTitle: incomplete[0]?.title ?? null,
  };
}

const visibleActions = computed(() =>
  actions.value.filter(
    (item) =>
      projectFilter.value === "all" || item.projectId === projectFilter.value,
  ),
);

const visibleBoard = computed(() =>
  buildWorkBoard(
    boardInputs.value.filter(
      (item) =>
        projectFilter.value === "all" || item.projectId === projectFilter.value,
    ),
  ),
);

const empty = computed(
  () =>
    !visibleActions.value.length &&
    Object.values(visibleBoard.value.columns).every((items) => !items.length),
);

async function load() {
  const backend = getBackend();
  if (!backend || !auth.user) return;
  loading.value = true;
  error.value = null;
  try {
    await projects.load();
    const repository = createRepository(backend.client);
    const rows = await Promise.all(
      projects.activeItems.map(async (summary) => {
        const projectId = summary.project.id;
        const [
          tasks,
          dependencies,
          offers,
          collaborators,
          reviews,
          joinRequests,
          report,
        ] = await Promise.all([
          repository.listTasks(projectId),
          repository.listTaskDependencies(projectId),
          repository.listAssignmentOffers(projectId),
          repository.listTaskCollaborators(projectId),
          repository.listReviews(projectId),
          summary.capabilities.canReviewJoinRequest
            ? repository.listJoinRequests(projectId)
            : Promise.resolve([]),
          summary.capabilities.canConfirmContributionReport
            ? repository.getContributionReport(projectId)
            : Promise.resolve(null),
        ]);
        const confirmations = report
          ? await repository.listContributionConfirmations(report.reportId)
          : [];
        return {
          summary,
          tasks,
          dependencies,
          offers,
          collaborators,
          reviews,
          joinRequests,
          report,
          confirmations,
        };
      }),
    );

    const userId = auth.user.id;
    const nextActions: ActionItem[] = [];
    const nextBoard: WorkTaskInput[] = [];

    for (const row of rows) {
      const projectId = row.summary.project.id;
      const projectName = row.summary.project.name;
      const taskById = new Map(row.tasks.map((task) => [task.id, task]));

      for (const offer of row.offers) {
        if (offer.state !== "pending" || offer.target_user_id !== userId)
          continue;
        const task = taskById.get(offer.task_id);
        if (!task) continue;
        nextActions.push({
          id: `${projectId}:assignment:${offer.id}`,
          projectId,
          projectName,
          title: task.title,
          detail: "任务指派等待你接受或拒绝",
          kindLabel: "任务待接受",
          task,
        });
      }

      for (const collaborator of row.collaborators) {
        if (collaborator.state !== "pending" || collaborator.user_id !== userId)
          continue;
        const task = taskById.get(collaborator.task_id);
        if (!task) continue;
        nextActions.push({
          id: `${projectId}:collaboration:${collaborator.id}`,
          projectId,
          projectName,
          title: task.title,
          detail: "协作者邀请等待你接受或拒绝",
          kindLabel: "协作邀请",
          task,
        });
      }

      for (const task of row.tasks) {
        const acceptedForTask = row.collaborators.filter(
          (collaborator) =>
            collaborator.task_id === task.id &&
            collaborator.state === "accepted",
        );
        const isPrimary = task.assignee_id === userId;
        const isCollaborator = acceptedForTask.some(
          (collaborator) => collaborator.user_id === userId,
        );
        if (!isPrimary && !isCollaborator) continue;
        const review = latestReview(task.id, row.reviews);
        const dependency = dependencyInfo(task, row.tasks, row.dependencies);
        nextBoard.push({
          task,
          projectId,
          projectName,
          responsibility: isCollaborator
            ? { kind: "collaborator" }
            : { kind: "primary", collaboratorCount: acceptedForTask.length },
          dependencyBlocked: dependency.blocked,
          upstreamTitle: dependency.upstreamTitle,
          latestReviewDecision: review?.decision,
          latestReviewReason: review?.rejection_reason,
        });

        if (review?.decision === "request_changes") {
          nextActions.push({
            id: `${projectId}:changes:${task.id}`,
            projectId,
            projectName,
            title: task.title,
            detail: review.rejection_reason ?? "验收要求修改后重新提交",
            kindLabel: "需要修改",
            task,
          });
        }
      }

      for (const round of row.reviews) {
        const task = taskById.get(round.task_id);
        if (
          !task ||
          !canReviewTaskSubmission({
            role: row.summary.role,
            currentUserId: userId,
            task,
            round,
          })
        ) {
          continue;
        }
        nextActions.push({
          id: `${projectId}:review:${round.id}`,
          projectId,
          projectName,
          title: `验收「${task.title}」`,
          detail: `第 ${round.round_number} 轮`,
          kindLabel: "验收",
          route: {
            name: "review-detail",
            params: { projectId, reviewRoundId: round.id },
          },
        });
      }

      for (const request of row.joinRequests) {
        if (request.state !== "pending") continue;
        nextActions.push({
          id: `${projectId}:join:${request.id}`,
          projectId,
          projectName,
          title: "处理加入项目申请",
          detail: new Date(request.created_at).toLocaleString(),
          kindLabel: "加入申请",
          route: {
            name: "project-invitations",
            params: { projectId },
          },
        });
      }

      if (
        row.report?.state === "draft" &&
        !row.confirmations.some(
          (confirmation) => confirmation.user_id === userId,
        )
      ) {
        nextActions.push({
          id: `${projectId}:report:${row.report.reportId}`,
          projectId,
          projectName,
          title: "确认贡献报告",
          detail: `报告 v${row.report.version} 等待你的确认`,
          kindLabel: "报告确认",
          route: {
            name: "project-contributions",
            params: { projectId },
          },
        });
      }
    }

    actions.value = nextActions;
    boardInputs.value = nextBoard;
  } catch {
    error.value = "无法加载跨项目工作，请重试。";
  } finally {
    loading.value = false;
  }
}

function rememberAndOpen(task: TaskRow, projectId: string) {
  navigation.rememberSource({
    routeName: "projects-todos",
    projectId,
    taskId: task.id,
    scrollY: window.scrollY,
    state: { projectFilter: projectFilter.value },
  });
  navigation.openDrawer(projectId, task.id);
}

async function openAction(id: string) {
  const action = visibleActions.value.find((item) => item.id === id);
  if (!action) return;
  if (action.task) {
    rememberAndOpen(action.task, action.projectId);
    return;
  }
  if (action.route) await router.push(action.route);
}

async function viewCompletedHistory() {
  if (projectFilter.value === "all") return;
  await router.push({
    name: "project-tasks",
    params: { projectId: projectFilter.value },
  });
}

function openTask(item: WorkTaskItem) {
  rememberAndOpen(item.task, item.projectId);
}

onMounted(() => void load());
onActivated(() => {
  const source = navigation.source;
  if (source?.routeName === "projects-todos") {
    projectFilter.value = String(source.state.projectFilter ?? "all");
  }
  void load();
});
</script>

<template>
  <div class="xiaozhuwork-page work-page">
    <header class="page-heading">
      <div>
        <h1>我的工作</h1>
      </div>
      <label class="project-filter">
        <span class="sr-only">项目筛选</span>
        <select v-model="projectFilter">
          <option value="all">全部项目</option>
          <option
            v-for="item in projects.activeItems"
            :key="item.project.id"
            :value="item.project.id"
          >
            {{ item.project.name }}
          </option>
        </select>
      </label>
    </header>

    <PageState
      :loading="loading"
      :error="error"
      :empty="empty"
      empty-title="当前没有待处理工作"
      empty-description="新的任务、验收、加入申请或确认事项会出现在这里。"
      @retry="load"
    >
      <div class="work-content">
        <ActionRequiredSection :items="visibleActions" @open="openAction" />
        <section aria-labelledby="my-tasks-title">
          <h2 id="my-tasks-title" class="section-title">我的任务</h2>
          <WorkBoard
            :model="visibleBoard"
            show-project
            :completed-history-available="projectFilter !== 'all'"
            @open="openTask"
            @view-completed-history="viewCompletedHistory"
          />
        </section>
      </div>
    </PageState>
  </div>
</template>

<style scoped>
.work-page {
  display: grid;
  gap: 18px;
}
.project-filter select {
  min-height: 40px;
  padding: 0 34px 0 11px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-surface);
  color: var(--tu-ink);
}
.work-content {
  display: grid;
  gap: 18px;
}
.section-title {
  margin: 0 0 10px;
  font-size: 17px;
}
@media (max-width: 700px) {
  .page-heading {
    align-items: stretch;
  }
  .project-filter select {
    width: 100%;
  }
}
</style>
