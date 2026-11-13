<script setup lang="ts">
import { computed, nextTick, onActivated, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { showConfirmDialog, showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import MemberList from "@/components/member/MemberList.vue";
import MemberTaskFlow from "@/components/member/MemberTaskFlow.vue";
import MemberWorkOverview from "@/components/member/MemberWorkOverview.vue";
import { vDismissibleDetails } from "@/directives/dismissible-details";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import {
  ROLE_LABELS,
  normalizeProjectRole,
  type ProjectRole,
} from "@/domain/access-control";
import { displayStatusLabel } from "@/domain/presentation-labels";
import {
  memberPrimaryTasks,
  nextExpandedMemberId,
  type MemberFlowMember,
  type MemberFlowTask,
  type MemberTimeRange,
} from "@/domain/member-team-work";
import { buildMemberWorkSummaries } from "@/domain/member-work-facts";
import { useTaskNavigationStore } from "@/stores/task-navigation";
import type { MembershipRow } from "@/types/ui";

const route = useRoute();
const router = useRouter();
const { workspace, projectId, reload } = useWorkspaceRoute();
const navigation = useTaskNavigationStore();

const selectedMemberId = ref<string | null>(null);
const expandedMemberId = ref<string | null>(null);
const remainingExpandedMemberId = ref<string | null>(null);
const range = ref<MemberTimeRange>("month");
const flowScroll = ref({ left: 0, top: 0 });
const flowRef = ref<InstanceType<typeof MemberTaskFlow> | null>(null);
const memberMenuOpen = ref(false);

const members = computed<MemberFlowMember[]>(() =>
  workspace.members
    .filter((member) => member.member_state === "active")
    .map((member) => ({
      id: member.id,
      userId: member.user_id,
      displayName: member.display_name_snapshot?.trim() || "未命名成员",
      roleLabel:
        ROLE_LABELS[
          normalizeProjectRole({
            role: member.role,
            isObserver: member.is_observer,
          })
        ],
      joinedAt: member.joined_at,
      primaryCount: member.user_id
        ? workspace.tasks.filter(
            (task) =>
              task.assignee_id === member.user_id && task.status !== "canceled",
          ).length
        : 0,
      collaboratorCount: member.user_id
        ? (workspace.taskCollaborators ?? []).filter(
            (item) =>
              item.user_id === member.user_id && item.state === "accepted",
          ).length
        : 0,
    })),
);

const flowTasks = computed<MemberFlowTask[]>(() =>
  workspace.tasks.map((task) => {
    const displayStatus = workspace.taskDisplayStatus(task);
    return {
      id: task.id,
      title: task.title,
      primaryUserId: task.assignee_id,
      acceptedAt: task.accepted_at,
      createdAt: task.created_at,
      deadlineAt: task.deadline_at,
      completedAt: task.completed_at,
      status: displayStatus,
      statusLabel: displayStatusLabel(displayStatus),
      collaboratorCount: (workspace.taskCollaborators ?? []).filter(
        (item) => item.task_id === task.id && item.state === "accepted",
      ).length,
    };
  }),
);

const summaries = computed(() =>
  buildMemberWorkSummaries({
    members: workspace.members,
    tasks: workspace.tasks,
    reviews: workspace.reviews,
  }),
);

const selectedMember = computed(
  () =>
    members.value.find((member) => member.id === selectedMemberId.value) ??
    null,
);

const flowMembers = computed(() =>
  selectedMember.value ? [selectedMember.value] : members.value,
);

const selectedSummary = computed(
  () =>
    summaries.value.find(
      (summary) => summary.memberId === selectedMemberId.value,
    ) ?? null,
);

const selectedPrimaryTasks = computed(() =>
  selectedMember.value
    ? memberPrimaryTasks(selectedMember.value, flowTasks.value)
    : [],
);

const selectedCollaboratorTasks = computed<MemberFlowTask[]>(() => {
  if (!selectedMember.value?.userId) return [];
  const taskIds = new Set(
    (workspace.taskCollaborators ?? [])
      .filter(
        (item) =>
          item.user_id === selectedMember.value!.userId &&
          item.state === "accepted",
      )
      .map((item) => item.task_id),
  );
  return flowTasks.value.filter(
    (task) => task.status !== "canceled" && taskIds.has(task.id),
  );
});

function roleOf(member: MembershipRow) {
  return normalizeProjectRole({
    role: member.role,
    isObserver: member.is_observer,
  });
}

function memberRow(memberId: string) {
  return workspace.members.find((member) => member.id === memberId) ?? null;
}

function editableRoles(
  member: MembershipRow,
): Exclude<ProjectRole, "leader">[] {
  if (!workspace.capabilities.canManageMembers) return [];
  const targetRole = roleOf(member);
  if (targetRole === "leader") return [];
  if (workspace.role === "admin") {
    return targetRole === "member" || targetRole === "observer"
      ? ["member", "observer"]
      : [];
  }
  return ["admin", "member", "observer"];
}

function canRemove(member: MembershipRow) {
  const targetRole = roleOf(member);
  if (!workspace.capabilities.canManageMembers || targetRole === "leader")
    return false;
  if (workspace.role === "admin" && targetRole === "admin") return false;
  return member.user_id !== workspace.currentUserId;
}

function canTransfer(member: MembershipRow) {
  if (
    workspace.role !== "leader" ||
    member.user_id === workspace.currentUserId
  ) {
    return false;
  }
  const targetRole = roleOf(member);
  return targetRole === "admin" || targetRole === "member";
}

async function changeRole(member: MembershipRow, event: Event) {
  const targetRole = (event.target as HTMLSelectElement).value as Exclude<
    ProjectRole,
    "leader"
  >;
  if (targetRole === roleOf(member)) return;
  const result = await workspace.updateMemberRole(member, targetRole);
  showToast(
    result.ok ? "成员角色已更新" : workspace.actionError || "角色更新失败",
  );
}

async function removeMember(member: MembershipRow) {
  try {
    await showConfirmDialog({
      title: "移除成员",
      message:
        "移除后该成员将失去项目访问权限；可安全释放的进行中任务会回到待认领。",
      confirmButtonText: "确认移除",
    });
  } catch {
    return;
  }
  const result = await workspace.removeMember(member);
  showToast(result.ok ? "成员已移除" : workspace.actionError || "移除失败");
}

async function transferLeadership(member: MembershipRow) {
  try {
    await showConfirmDialog({
      title: "转让组长",
      message: "转让完成后，你将降为普通成员，新组长立即获得组长权限。",
      confirmButtonText: "确认转让",
    });
  } catch {
    return;
  }
  const result = await workspace.transferLeadership(member);
  showToast(result.ok ? "组长已转让" : workspace.actionError || "转让失败");
}

function onMemberMenuToggle(event: Event) {
  memberMenuOpen.value = (event.currentTarget as HTMLDetailsElement).open;
}

async function setSelectedMember(memberId: string | null) {
  selectedMemberId.value = memberId;
  expandedMemberId.value = null;
  remainingExpandedMemberId.value = null;
  memberMenuOpen.value = false;
  const query = { ...route.query };
  if (memberId) query.member = memberId;
  else delete query.member;
  await router.replace({ query });
}

function toggleMember(memberId: string) {
  expandedMemberId.value = nextExpandedMemberId(
    expandedMemberId.value,
    memberId,
  );
  remainingExpandedMemberId.value = null;
}

function toggleRemaining(memberId: string) {
  remainingExpandedMemberId.value =
    remainingExpandedMemberId.value === memberId ? null : memberId;
}

function updateScroll(position: { left: number; top: number }) {
  flowScroll.value = position;
}

function openTask(taskId: string) {
  navigation.rememberSource({
    routeName: "project-members",
    projectId: projectId.value,
    taskId,
    scrollY: window.scrollY,
    state: {
      member: selectedMemberId.value,
      expandedMember: expandedMemberId.value,
      remainingMember: remainingExpandedMemberId.value,
      range: range.value,
      flowLeft: flowScroll.value.left,
      flowTop: flowScroll.value.top,
    },
  });
  navigation.openDrawer(projectId.value, taskId);
}

function openFlowTask(task: MemberFlowTask) {
  openTask(task.id);
}

function initializeMemberFromQuery() {
  const raw =
    typeof route.query.member === "string" ? route.query.member : null;
  if (!raw) return;
  const matched = members.value.find(
    (member) => member.id === raw || member.userId === raw,
  );
  if (!matched) return;
  selectedMemberId.value = matched.id;
}

async function restoreNavigationState() {
  const source = navigation.source;
  if (source?.routeName !== "project-members") return;
  selectedMemberId.value =
    typeof source.state.member === "string" ? source.state.member : null;
  expandedMemberId.value =
    typeof source.state.expandedMember === "string"
      ? source.state.expandedMember
      : null;
  remainingExpandedMemberId.value =
    typeof source.state.remainingMember === "string"
      ? source.state.remainingMember
      : null;
  if (
    source.state.range === "week" ||
    source.state.range === "month" ||
    source.state.range === "all"
  ) {
    range.value = source.state.range;
  }
  flowScroll.value = {
    left: typeof source.state.flowLeft === "number" ? source.state.flowLeft : 0,
    top: typeof source.state.flowTop === "number" ? source.state.flowTop : 0,
  };
  await nextTick();
  await flowRef.value?.restoreScroll(flowScroll.value);
}

watch(members, initializeMemberFromQuery, { immediate: true });
watch(
  () => route.query.member,
  () => initializeMemberFromQuery(),
);

async function ensureReviews() {
  await workspace.loadReviews();
}

onActivated(() => {
  void ensureReviews().then(() => restoreNavigationState());
});
void ensureReviews();
</script>

<template>
  <div class="xiaozhuwork-page members-page">
    <header class="page-heading">
      <div>
        <h1>成员与团队工作</h1>
      </div>
      <RouterLink
        v-if="workspace.role === 'leader'"
        :to="{ name: 'project-permissions', params: { projectId } }"
      >
        <van-button plain>权限委派</van-button>
      </RouterLink>
      <RouterLink
        v-if="workspace.capabilities.canManageInvites"
        :to="{ name: 'project-invitations', params: { projectId } }"
      >
        <van-button type="primary">邀请成员</van-button>
      </RouterLink>
    </header>

    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="!workspace.project || !workspace.membership"
      :empty="!members.length"
      empty-title="当前没有项目成员"
      @retry="reload"
    >
      <div class="members-layout">
        <aside
          class="member-sidebar"
          :class="{ 'is-mobile-focused': selectedMemberId }"
        >
          <MemberList
            :members="members"
            :selected-member-id="selectedMemberId"
            @select="setSelectedMember"
          />
        </aside>

        <main class="team-workspace">
          <button
            v-if="selectedMemberId"
            type="button"
            class="mobile-member-back"
            @click="setSelectedMember(null)"
          >
            ← 成员
          </button>
          <section class="timeline-card">
            <MemberTaskFlow
              ref="flowRef"
              :members="flowMembers"
              :tasks="flowTasks"
              :title="selectedMember ? '任务时间' : '团队 MemberTaskFlow'"
              :range="range"
              :expanded-member-id="expandedMemberId"
              :remaining-expanded-member-id="remainingExpandedMemberId"
              @update:range="range = $event"
              @toggle-member="toggleMember"
              @toggle-remaining="toggleRemaining"
              @open-task="openFlowTask"
              @update:scroll-position="updateScroll"
            />
          </section>

          <section v-if="selectedSummary" class="member-detail-card">
            <MemberWorkOverview
              :summary="selectedSummary"
              :primary-tasks="selectedPrimaryTasks"
              :collaborator-tasks="selectedCollaboratorTasks"
              @open-task="openTask"
            />

            <details
              v-if="
                selectedMemberId &&
                memberRow(selectedMemberId) &&
                workspace.capabilities.canManageMembers
              "
              v-dismissible-details
              class="member-management"
              :open="memberMenuOpen"
              @toggle="onMemberMenuToggle"
            >
              <summary
                :aria-label="`管理 ${selectedSummary.displayName}`"
                aria-haspopup="menu"
                :aria-expanded="memberMenuOpen"
              >
                ⋯
              </summary>
              <div
                v-if="memberRow(selectedMemberId)"
                class="management-menu"
                role="menu"
              >
                <label
                  v-if="editableRoles(memberRow(selectedMemberId)!).length"
                >
                  <span>修改角色</span>
                  <select
                    :value="roleOf(memberRow(selectedMemberId)!)"
                    :disabled="workspace.pendingAction === 'member-role'"
                    @change="changeRole(memberRow(selectedMemberId)!, $event)"
                  >
                    <option
                      v-for="role in editableRoles(
                        memberRow(selectedMemberId)!,
                      )"
                      :key="role"
                      :value="role"
                    >
                      {{ ROLE_LABELS[role] }}
                    </option>
                  </select>
                </label>
                <button
                  type="button"
                  @click="setSelectedMember(selectedMemberId)"
                >
                  查看成员详情
                </button>
                <hr />
                <button
                  v-if="canTransfer(memberRow(selectedMemberId)!)"
                  type="button"
                  @click="transferLeadership(memberRow(selectedMemberId)!)"
                >
                  转让组长
                </button>
                <button
                  v-if="canRemove(memberRow(selectedMemberId)!)"
                  type="button"
                  class="danger"
                  @click="removeMember(memberRow(selectedMemberId)!)"
                >
                  移除成员
                </button>
              </div>
            </details>
          </section>
        </main>
      </div>
    </PageState>
  </div>
</template>

<style scoped>
.members-page {
  display: grid;
  gap: 16px;
}
.members-layout {
  display: grid;
  grid-template-columns: minmax(220px, 280px) minmax(0, 1fr);
  gap: 14px;
  align-items: start;
}
.member-sidebar {
  position: sticky;
  top: 138px;
  padding: var(--space-sm) 0;
  border-top: 1px solid var(--tu-border);
}
.team-workspace {
  min-width: 0;
  display: grid;
  gap: 14px;
}
.timeline-card,
.member-detail-card {
  padding: var(--space-md) 0;
  border-top: 1px solid var(--tu-border);
}
.member-detail-card {
  position: relative;
}
.member-management {
  position: absolute;
  top: 12px;
  right: 12px;
}
.member-management > summary {
  width: 36px;
  height: 36px;
  display: grid;
  place-items: center;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  background: var(--tu-surface);
  cursor: pointer;
  list-style: none;
  font-size: 20px;
}
.member-management > summary::-webkit-details-marker {
  display: none;
}
.management-menu {
  position: absolute;
  top: 42px;
  right: 0;
  z-index: 20;
  width: 210px;
  display: grid;
  gap: 6px;
  padding: 9px;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-panel);
  background: var(--tu-surface);
  box-shadow: var(--tu-shadow);
}
.management-menu label {
  display: grid;
  gap: 5px;
  color: var(--tu-muted);
  font-size: 11px;
}
.management-menu select,
.management-menu button {
  min-height: 36px;
  border: 0;
  border-radius: 7px;
  background: var(--tu-subtle-surface);
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.management-menu select {
  border: 1px solid var(--tu-border);
}
.management-menu button {
  padding: 0 9px;
}
.management-menu hr {
  width: 100%;
  border: 0;
  border-top: 1px solid var(--tu-border);
}
.management-menu .danger {
  color: var(--van-danger-color);
}
.mobile-member-back {
  display: none;
}
@media (max-width: 767px) {
  .members-layout {
    grid-template-columns: 1fr;
  }
  .member-sidebar {
    position: static;
  }
  .member-sidebar.is-mobile-focused {
    display: none;
  }
  .mobile-member-back {
    width: fit-content;
    display: inline-flex;
    align-items: center;
    min-height: 36px;
    padding: 0;
    border: 0;
    background: transparent;
    color: var(--tu-blue-strong);
    font: inherit;
    font-weight: 700;
    cursor: pointer;
  }
  .timeline-card {
    overflow: hidden;
  }
}
</style>
