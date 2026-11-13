<script setup lang="ts">
defineOptions({ name: "ProjectOverviewView" });

import {
  computed,
  onActivated,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from "vue";
import PageState from "@/components/common/PageState.vue";
import HelpIntroCard from "@/components/help/HelpIntroCard.vue";
import type { HelpHintKey } from "@/services/help-preferences";
import { useHelpStore } from "@/stores/help";
import { useAuthStore } from "@/stores/auth";
import MobileProjectOverview from "@/components/overview/MobileProjectOverview.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import TaskFlowGraph from "@/components/TaskFlowGraph.vue";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import {
  buildMobileOverviewTodoItems,
  countMembersWithDueSoonTasks,
  summarizeMobileTaskFlow,
} from "@/domain/mobile-project-overview";
import { buildProjectActionItems } from "@/domain/project-action-items";
import { taskNeedsAttention } from "@/domain/task-display";
import type { TaskGraphScope } from "@/domain/task-dependency-graph";
import {
  buildProjectWorkInputs,
  classifyWorkTask,
  type WorkTaskItem,
} from "@/domain/todo-workboard";
import { useNotificationsStore } from "@/stores/notifications";
import { useTaskNavigationStore } from "@/stores/task-navigation";
import type { TaskRow } from "@/types/ui";

const { workspace, projectId, reload } = useWorkspaceRoute();
const navigation = useTaskNavigationStore();
const notifications = useNotificationsStore();
const auth = useAuthStore();
const help = useHelpStore();
const introKey = computed<HelpHintKey>(() => `v1:intro:${workspace.role}`);
const showIntro = computed(() =>
  Boolean(
    auth.user &&
    workspace.project &&
    workspace.membership &&
    !workspace.loading &&
    !workspace.error &&
    help.loadedForUserId === auth.user.id &&
    !help.dismissed.has(introKey.value),
  ),
);
watch(
  () => auth.user?.id,
  (id) => {
    if (id) void help.loadForUser(id);
    else help.reset();
  },
  { immediate: true },
);
function dismissIntro() {
  void help.dismiss(introKey.value);
}

const mobileMediaQuery =
  typeof window !== "undefined" && typeof window.matchMedia === "function"
    ? window.matchMedia("(max-width: 767px)")
    : null;
const isMobileOverview = ref(mobileMediaQuery?.matches ?? false);

function syncMobileOverview(event?: MediaQueryListEvent) {
  isMobileOverview.value = event?.matches ?? mobileMediaQuery?.matches ?? false;
}

onMounted(() => {
  syncMobileOverview();
  mobileMediaQuery?.addEventListener("change", syncMobileOverview);
});
onActivated(syncMobileOverview);
onBeforeUnmount(() => {
  mobileMediaQuery?.removeEventListener("change", syncMobileOverview);
});

const graphState = ref({
  zoom: 100,
  panX: 18,
  panY: 18,
  scope: "workflow" as TaskGraphScope,
  search: "",
  focusTaskId: null as string | null,
  historyExpanded: false,
});

const sourceState = computed(() => {
  const source = navigation.source;
  if (
    source?.routeName !== "project-overview" ||
    source.projectId !== projectId.value
  ) {
    return {};
  }
  return {
    zoom:
      typeof source.state.graphZoom === "number"
        ? source.state.graphZoom
        : undefined,
    panX:
      typeof source.state.graphPanX === "number"
        ? source.state.graphPanX
        : undefined,
    panY:
      typeof source.state.graphPanY === "number"
        ? source.state.graphPanY
        : undefined,
    scope:
      typeof source.state.graphScope === "string"
        ? (source.state.graphScope as TaskGraphScope)
        : undefined,
    search:
      typeof source.state.graphSearch === "string"
        ? source.state.graphSearch
        : undefined,
    focusTaskId:
      typeof source.state.graphFocusTaskId === "string" &&
      source.state.graphFocusTaskId
        ? source.state.graphFocusTaskId
        : null,
    historyExpanded: source.state.graphHistoryExpanded === true,
  };
});

const now = () => Date.now();

const attentionFacts = computed(() => {
  const openTasks = workspace.tasks.filter(
    (task) => task.status !== "completed" && task.status !== "canceled",
  );
  return [
    {
      label: "等待上游",
      value: openTasks.filter(
        (task) => workspace.dependencyState(task.id).blocked,
      ).length,
    },
    {
      label: "阻塞",
      value: openTasks.filter((task) => task.status === "blocked").length,
    },
    {
      label: "逾期",
      value: openTasks.filter((task) => Date.parse(task.deadline_at) < now())
        .length,
    },
    {
      label: "待验收",
      value: openTasks.filter((task) => task.status === "awaiting_review")
        .length,
    },
    {
      label: "待接受",
      value: openTasks.filter((task) => task.assignment_state !== "assigned")
        .length,
    },
  ];
});

function attentionReason(task: TaskRow) {
  if (workspace.dependencyState(task.id).blocked) return "等待上游";
  if (task.status === "blocked") return "阻塞";
  if (Date.parse(task.deadline_at) < now()) return "已逾期";
  if (task.status === "awaiting_review") return "待验收";
  if (task.assignment_state !== "assigned") return "待接受";
  return workspace.taskDisplayStatus(task);
}

const attentionTasks = computed(() =>
  workspace.tasks
    .filter(
      (task) =>
        taskNeedsAttention(task) ||
        workspace.dependencyState(task.id).blocked ||
        task.assignment_state !== "assigned",
    )
    .sort(
      (left, right) =>
        Date.parse(left.deadline_at) - Date.parse(right.deadline_at),
    )
    .slice(0, 5),
);

const memberSummary = computed(() =>
  workspace.members
    .map((member) => {
      const primaryTasks = workspace.tasks.filter(
        (task) => task.assignee_id === member.user_id,
      );
      const dueSoon = primaryTasks.filter((task) => {
        if (task.status === "completed" || task.status === "canceled")
          return false;
        const remaining = Date.parse(task.deadline_at) - now();
        return remaining >= 0 && remaining <= 3 * 86_400_000;
      }).length;
      return {
        id: member.id,
        userId: member.user_id,
        name: member.display_name_snapshot || "未命名成员",
        primaryCount: primaryTasks.length,
        dueSoon,
      };
    })
    .sort((left, right) => right.primaryCount - left.primaryCount)
    .slice(0, 5),
);

const recentNotifications = computed(() =>
  notifications.items
    .filter((item) => item.project_id === projectId.value)
    .slice(0, 3),
);

const mobileActions = computed(() =>
  buildProjectActionItems({
    projectId: projectId.value,
    currentUserId: workspace.currentUserId,
    role: workspace.role,
    capabilities: workspace.capabilities,
    tasks: workspace.tasks,
    assignmentOffers: workspace.assignmentOffers ?? [],
    reviews: workspace.reviews ?? [],
    joinRequests: workspace.joinRequests ?? [],
    contributionReport: workspace.contributionReport ?? null,
    contributionConfirmations: workspace.contributionConfirmations ?? [],
    findCollaborator: (taskId) => workspace.findCollaborator?.(taskId),
  }),
);

const mobileWorkItems = computed<WorkTaskItem[]>(() =>
  buildProjectWorkInputs({
    tasks: workspace.tasks,
    reviews: workspace.reviews ?? [],
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
  })
    .map(classifyWorkTask)
    .filter((item): item is WorkTaskItem => item !== null),
);

const mobileTodoItems = computed(() =>
  buildMobileOverviewTodoItems({
    actions: mobileActions.value,
    workItems: mobileWorkItems.value,
  }),
);

const mobileFlowSummary = computed(() =>
  summarizeMobileTaskFlow(
    workspace.tasks,
    workspace.taskDependencies,
    (taskId) => workspace.dependencyState?.(taskId).blocked ?? false,
  ),
);

const mobileDueSoonMemberCount = computed(() =>
  countMembersWithDueSoonTasks(workspace.tasks, workspace.members),
);

function updateGraphState(state: typeof graphState.value) {
  graphState.value = state;
}

function openTask(taskId: string) {
  const task = workspace.findTask(taskId);
  if (!task) return;
  const state = graphState.value;
  navigation.rememberSource({
    routeName: "project-overview",
    projectId: projectId.value,
    taskId,
    scrollY: window.scrollY,
    state: {
      graphZoom: state.zoom,
      graphPanX: state.panX,
      graphPanY: state.panY,
      graphScope: state.scope,
      graphSearch: state.search,
      graphFocusTaskId: state.focusTaskId ?? "",
      graphHistoryExpanded: state.historyExpanded,
    },
  });
  navigation.openDrawer(projectId.value, task.id);
}

function memberName(userId: string | null | undefined) {
  return userId ? workspace.memberName(userId) : "未分配";
}
</script>

<template>
  <div class="xiaozhuwork-page overview-page">
    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="!workspace.project || !workspace.membership"
      :empty="!workspace.project"
      empty-title="项目不存在或无权访问"
      @retry="reload"
    >
      <template v-if="workspace.project">
        <HelpIntroCard
          v-if="showIntro"
          :role="workspace.role"
          :member-count="workspace.members.length"
          :task-count="workspace.tasks.length"
          :project-id="projectId"
          :archived="Boolean(workspace.project.archived_at)"
          :sync-error="help.syncError"
          @dismiss="dismissIntro"
        />
        <MobileProjectOverview
          v-if="isMobileOverview"
          :project-id="projectId"
          :archived="Boolean(workspace.project.archived_at)"
          :project-name="workspace.project.name"
          :course-name="workspace.project.course_name"
          :deadline-at="workspace.project.deadline_at"
          :member-count="workspace.members.length"
          :todo-items="mobileTodoItems"
          :flow-summary="mobileFlowSummary"
          :due-soon-member-count="mobileDueSoonMemberCount"
          :tasks="workspace.tasks"
          :dependencies="workspace.taskDependencies"
          :member-name="memberName"
          :current-user-id="workspace.currentUserId"
          :initial-graph-state="sourceState"
          @open-task="openTask"
          @graph-state-change="updateGraphState"
        />
        <header v-if="!isMobileOverview" class="overview-head">
          <div class="overview-title">
            <span class="project-state">
              {{ workspace.project.archived_at ? "已归档" : "进行中" }}
            </span>
            <h1>{{ workspace.project.name }}</h1>
            <p>
              {{ workspace.project.course_name || "未设置课程" }}
              <span aria-hidden="true">·</span>
              {{ workspace.members.length }} 位成员
              <span aria-hidden="true">·</span>
              DDL
              {{ new Date(workspace.project.deadline_at).toLocaleDateString() }}
            </p>
          </div>
          <div class="head-actions">
            <RouterLink
              v-if="workspace.capabilities.canManageInvites"
              :to="{ name: 'project-invitations', params: { projectId } }"
            >
              <van-button plain>邀请成员</van-button>
            </RouterLink>
            <RouterLink
              v-if="workspace.capabilities.canCreateTask"
              :to="{ name: 'task-create', params: { projectId } }"
            >
              <van-button type="primary">创建任务</van-button>
            </RouterLink>
          </div>
        </header>

        <div v-if="!isMobileOverview" class="overview-grid">
          <section class="graph-column" aria-labelledby="task-flow-title">
            <div class="section-heading">
              <div>
                <h2 id="task-flow-title">任务工作流</h2>
                <p>查看依赖关系；缩小时优先减少信息，而不是牺牲可读性。</p>
              </div>
              <span>{{ workspace.tasks.length }} 项任务</span>
            </div>

            <TaskFlowGraph
              :tasks="workspace.tasks"
              :dependencies="workspace.taskDependencies"
              :member-name="memberName"
              :current-user-id="workspace.currentUserId"
              :initial-state="sourceState"
              @state-change="updateGraphState"
              @open-task="openTask"
            />
          </section>

          <aside class="overview-rail" aria-label="项目摘要">
            <section class="rail-card attention-card">
              <div class="rail-heading">
                <h2>需要关注</h2>
                <RouterLink
                  :to="{ name: 'project-todos', params: { projectId } }"
                >
                  查看全部
                </RouterLink>
              </div>
              <div class="attention-facts">
                <span
                  v-for="fact in attentionFacts"
                  :key="fact.label"
                  :class="{ active: fact.value > 0 }"
                >
                  {{ fact.label }} <strong>{{ fact.value }}</strong>
                </span>
              </div>
              <div v-if="attentionTasks.length" class="rail-list">
                <button
                  v-for="task in attentionTasks"
                  :key="task.id"
                  type="button"
                  @click="openTask(task.id)"
                >
                  <span>
                    <strong>{{ task.title }}</strong>
                    <small>
                      {{ attentionReason(task) }} ·
                      {{ memberName(task.assignee_id) }}
                    </small>
                  </span>
                  <StatusBadge :status="task.status" />
                </button>
              </div>
              <p v-else class="rail-empty">当前没有需要立即处理的事项。</p>
            </section>

            <section class="rail-card">
              <div class="rail-heading">
                <h2>成员工作摘要</h2>
                <RouterLink
                  :to="{ name: 'project-members', params: { projectId } }"
                >
                  查看成员工作
                </RouterLink>
              </div>
              <div class="member-summary">
                <div v-for="member in memberSummary" :key="member.id">
                  <strong>{{ member.name }}</strong>
                  <span>
                    主负责 {{ member.primaryCount }}
                    <template v-if="member.dueSoon > 0">
                      · {{ member.dueSoon }} 项临期
                    </template>
                  </span>
                </div>
              </div>
              <p v-if="!memberSummary.length" class="rail-empty">
                暂无成员数据。
              </p>
            </section>

            <section class="rail-card">
              <div class="rail-heading">
                <h2>最近通知</h2>
                <RouterLink to="/notifications">查看全部</RouterLink>
              </div>
              <div
                v-if="recentNotifications.length"
                class="notification-summary"
              >
                <article v-for="item in recentNotifications" :key="item.id">
                  <span
                    v-if="!item.read_at"
                    class="unread-dot"
                    aria-label="未读"
                  />
                  <div>
                    <strong>{{ item.title }}</strong>
                    <p>{{ item.message }}</p>
                    <time>{{
                      new Date(item.created_at).toLocaleString()
                    }}</time>
                  </div>
                </article>
              </div>
              <p v-else class="rail-empty">当前项目暂无最近通知。</p>
            </section>
          </aside>
        </div>
      </template>
    </PageState>
  </div>
</template>

<style scoped>
.overview-page {
  min-width: 0;
  width: 100%;
}

.overview-head {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 22px;
  padding: 4px 0;
}

.overview-title h1 {
  margin: 5px 0;
  overflow-wrap: anywhere;
  color: var(--tu-ink);
  font-size: var(--text-2xl);
  letter-spacing: -0.04em;
}

.overview-title p {
  margin: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 7px;
  color: var(--tu-muted);
  font-size: 14px;
}

.project-state {
  color: var(--tu-muted);
  font-size: 12px;
  font-weight: 700;
}

.head-actions {
  display: flex;
  gap: 9px;
  flex: 0 0 auto;
}

.overview-grid {
  min-width: 0;
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  align-items: start;
  gap: 16px;
}

.graph-column,
.overview-rail,
.rail-card,
.section-heading > div {
  min-width: 0;
}

.section-heading {
  min-height: 48px;
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: 20px;
  padding: 0 2px 10px;
}

.section-heading h2,
.rail-heading h2 {
  margin: 0;
  color: var(--tu-ink);
  font-size: 17px;
  letter-spacing: -0.02em;
}

.section-heading p {
  margin: 4px 0 0;
  color: var(--tu-muted);
  font-size: 12px;
}

.section-heading > span {
  color: var(--tu-muted);
  font-size: 12px;
}

.overview-rail {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: var(--space-sm);
}

.rail-card {
  padding: var(--space-md) 0;
  border-top: 1px solid var(--tu-border);
  background: transparent;
}

.rail-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.rail-heading a {
  color: var(--tu-blue-strong);
  font-size: 12px;
}

.attention-facts {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 12px;
}

.attention-facts span {
  padding: 5px 0;
  margin-right: var(--space-xs);
  color: var(--tu-muted);
  font-size: 11px;
}

.attention-facts span.active {
  color: var(--tu-warning-ink);
}

.attention-facts strong {
  margin-left: 2px;
  color: inherit;
}

.rail-list {
  display: grid;
  margin-top: 10px;
}

.rail-list button {
  min-height: 54px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 9px;
  padding: 9px 0;
  border: 0;
  border-top: 1px solid var(--tu-border);
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.rail-list button > span {
  min-width: 0;
}

.rail-list strong,
.rail-list small {
  display: block;
}

.rail-list strong {
  overflow: hidden;
  color: var(--tu-ink);
  font-size: 13px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.rail-list small {
  margin-top: 3px;
  color: var(--tu-muted);
  font-size: 11px;
}

.member-summary {
  display: grid;
  margin-top: 10px;
}

.member-summary > div {
  display: grid;
  gap: 3px;
  padding: 9px 0;
  border-top: 1px solid var(--tu-border);
}

.member-summary strong {
  color: var(--tu-ink);
  font-size: 13px;
}

.member-summary span {
  color: var(--tu-muted);
  font-size: 11px;
}

.notification-summary {
  display: grid;
  margin-top: 10px;
}

.notification-summary article {
  position: relative;
  display: grid;
  grid-template-columns: 8px 1fr;
  gap: 6px;
  padding: 10px 0;
  border-top: 1px solid var(--tu-border);
}

.notification-summary .unread-dot {
  width: 6px;
  height: 6px;
  margin-top: 5px;
  border-radius: 50%;
  background: var(--tu-blue);
}

.notification-summary article:not(:has(.unread-dot)) {
  grid-template-columns: 1fr;
}

.notification-summary strong {
  display: block;
  color: var(--tu-ink);
  font-size: 12px;
}

.notification-summary p {
  display: -webkit-box;
  margin: 3px 0;
  overflow: hidden;
  color: var(--tu-muted);
  font-size: 11px;
  line-height: 1.45;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.notification-summary time {
  color: var(--tu-muted);
  font-size: 10px;
}

.rail-empty {
  margin: 12px 0 0;
  color: var(--tu-muted);
  font-size: 12px;
  line-height: 1.55;
}

html[data-theme="dark"] .overview-title h1,
html[data-theme="dark"] .section-heading h2,
html[data-theme="dark"] .rail-heading h2 {
  color: var(--tu-ink);
}

@media (max-width: 1240px) {
  .overview-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 850px) {
  .section-heading {
    flex-wrap: wrap;
  }

  .overview-head {
    align-items: start;
    flex-direction: column;
  }

  .overview-rail {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 560px) {
  .head-actions {
    width: 100%;
  }

  .head-actions a {
    flex: 1;
  }

  .head-actions :deep(.van-button) {
    width: 100%;
  }
}
</style>
