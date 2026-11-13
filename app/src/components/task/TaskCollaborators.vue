<script setup lang="ts">
import { computed, ref } from "vue";
import { showConfirmDialog, showToast } from "vant";

import { canManageTaskCollaborators } from "@/domain/task-participant";
import {
  canManagePrimaryResponsibility,
  primaryHandoffCandidates,
} from "@/domain/task-primary-handoff";
import { useWorkspaceStore } from "@/stores/workspace";
import type { TaskRow } from "@/types/ui";

const props = defineProps<{ task: TaskRow }>();
const workspace = useWorkspaceStore();
const selectedUserId = ref("");
const selectedPrimaryTargetId = ref("");

const relations = computed(
  () => workspace.collaboratorsForTask?.(props.task.id) ?? [],
);
const activeRelations = computed(() =>
  relations.value.filter((item) =>
    ["pending", "accepted"].includes(item.state),
  ),
);
const pending = computed(() =>
  activeRelations.value.filter((item) => item.state === "pending"),
);
const mine = computed(
  () => workspace.findCollaborator?.(props.task.id) ?? null,
);
const canManage = computed(() =>
  canManageTaskCollaborators({
    role: workspace.role,
    currentUserId: workspace.currentUserId,
    task: props.task,
  }),
);
const pendingHandoff = computed(
  () => workspace.pendingPrimaryHandoff?.(props.task.id) ?? null,
);
const canManagePrimary = computed(() =>
  canManagePrimaryResponsibility({
    currentUserId: workspace.currentUserId,
    task: props.task,
    hasReviewHistory: props.task.first_submitted_at !== null,
    hasPendingTaskChange:
      workspace.findTaskChangeProposal?.(props.task.id)?.state === "pending",
  }),
);
const primaryCandidates = computed(() =>
  primaryHandoffCandidates({
    currentPrimaryId: props.task.assignee_id,
    members: workspace.members ?? [],
  }),
);
const inviteCandidates = computed(() => {
  const unavailable = new Set(
    activeRelations.value.map((relation) => relation.user_id).filter(Boolean),
  );
  return (workspace.members ?? []).filter(
    (member) =>
      member.user_id &&
      member.member_state === "active" &&
      member.role !== "observer" &&
      !member.is_observer &&
      member.user_id !== props.task.assignee_id &&
      !unavailable.has(member.user_id),
  );
});

function relationName(userId: string | null, snapshot: string | null) {
  return snapshot || workspace.memberName(userId);
}

async function invite() {
  if (!selectedUserId.value) return;
  const result = await workspace.inviteTaskCollaborator(
    props.task,
    selectedUserId.value,
  );
  showToast(result.ok ? "协作邀请已发送" : workspace.actionError || "邀请失败");
  if (result.ok) selectedUserId.value = "";
}

async function respond(action: "accept" | "reject") {
  if (!mine.value || mine.value.state !== "pending") return;
  const result = await workspace.respondToTaskCollaborator(mine.value, action);
  showToast(
    result.ok
      ? action === "accept"
        ? "已加入协作"
        : "已拒绝协作邀请"
      : workspace.actionError || "操作失败",
  );
}

async function remove(collaboratorId: string) {
  const relation = activeRelations.value.find(
    (item) => item.id === collaboratorId,
  );
  if (!relation) return;
  const result = await workspace.removeTaskCollaborator(relation);
  showToast(result.ok ? "已移除协作者" : workspace.actionError || "操作失败");
}

async function leave() {
  if (!mine.value || mine.value.state !== "accepted") return;
  const result = await workspace.leaveTaskCollaboration(mine.value);
  showToast(result.ok ? "已退出协作" : workspace.actionError || "操作失败");
}

async function requestPrimaryHandoff() {
  if (!selectedPrimaryTargetId.value || pendingHandoff.value) return;
  const result = await workspace.requestTaskPrimaryHandoff(
    props.task,
    selectedPrimaryTargetId.value,
  );
  showToast(
    result.ok ? "主负责人移交请求已发送" : workspace.actionError || "移交失败",
  );
  if (result.ok) selectedPrimaryTargetId.value = "";
}

async function respondPrimaryHandoff(action: "accept" | "reject") {
  if (!pendingHandoff.value) return;
  const result = await workspace.respondTaskPrimaryHandoff(
    props.task,
    pendingHandoff.value,
    action,
  );
  showToast(
    result.ok
      ? action === "accept"
        ? "已接受主负责人职责"
        : "已拒绝主负责人移交"
      : workspace.actionError || "操作失败",
  );
}

async function cancelPrimaryHandoff() {
  if (!pendingHandoff.value) return;
  const result = await workspace.cancelTaskPrimaryHandoff(
    props.task,
    pendingHandoff.value,
  );
  showToast(result.ok ? "已撤回移交请求" : workspace.actionError || "撤回失败");
}

async function unassignPrimary() {
  try {
    await showConfirmDialog({
      title: "卸任主负责人？",
      message:
        "任务会回到待认领状态，当前进度/阻塞说明会清空；已有文件、协作和依赖历史会保留。",
      confirmButtonText: "确认卸任",
    });
  } catch {
    return;
  }
  const result = await workspace.unassignTaskPrimary(props.task);
  showToast(
    result.ok ? "已卸任，任务回到待认领" : workspace.actionError || "卸任失败",
  );
}
</script>

<template>
  <section
    v-if="canManage || canManagePrimary || mine || pendingHandoff"
    class="task-collaborators"
    aria-label="任务责任管理"
  >
    <details
      :open="
        mine?.state === 'pending' ||
        pendingHandoff?.to_user_id === workspace.currentUserId
      "
    >
      <summary class="responsibility-toggle">管理责任与协作者</summary>
      <div class="responsibility-management">
        <div v-if="pendingHandoff" class="primary-transfer">
          <div>
            <strong>主负责人移交待确认</strong>
            <p class="muted">
              {{ pendingHandoff.from_user_name_snapshot }} →
              {{ pendingHandoff.to_user_name_snapshot }}
            </p>
          </div>
          <div
            v-if="pendingHandoff.to_user_id === workspace.currentUserId"
            class="inline-actions"
          >
            <van-button
              size="small"
              type="primary"
              :loading="workspace.pendingAction === 'primary-handoff-response'"
              @click="respondPrimaryHandoff('accept')"
            >
              接受主责
            </van-button>
            <van-button
              size="small"
              plain
              :loading="workspace.pendingAction === 'primary-handoff-response'"
              @click="respondPrimaryHandoff('reject')"
            >
              拒绝
            </van-button>
          </div>
          <van-button
            v-else-if="pendingHandoff.from_user_id === workspace.currentUserId"
            size="small"
            plain
            :loading="workspace.pendingAction === 'primary-handoff-cancel'"
            @click="cancelPrimaryHandoff"
          >
            撤回移交
          </van-button>
        </div>

        <div
          v-else-if="canManagePrimary"
          class="primary-transfer primary-transfer-form"
        >
          <label>
            <span>移交主负责人</span>
            <select
              v-model="selectedPrimaryTargetId"
              aria-label="选择新的主负责人"
            >
              <option value="">选择项目成员</option>
              <option
                v-for="member in primaryCandidates"
                :key="member.id"
                :value="member.user_id || ''"
              >
                {{ workspace.memberName(member.user_id) }}
              </option>
            </select>
          </label>
          <div class="inline-actions">
            <van-button
              size="small"
              type="primary"
              plain
              :disabled="!selectedPrimaryTargetId"
              :loading="workspace.pendingAction === 'primary-handoff-request'"
              @click="requestPrimaryHandoff"
            >
              发起移交
            </van-button>
            <van-button
              size="small"
              plain
              :loading="workspace.pendingAction === 'primary-unassign'"
              @click="unassignPrimary"
            >
              卸任并设为待认领
            </van-button>
          </div>
        </div>

        <div v-if="pending.length" class="pending-list">
          <strong>待响应邀请</strong>
          <div
            v-for="collaborator in pending"
            :key="collaborator.id"
            class="person-row"
          >
            <span>
              {{
                relationName(
                  collaborator.user_id,
                  collaborator.user_name_snapshot,
                )
              }}
              <small class="muted">待接受</small>
            </span>
            <div
              v-if="collaborator.user_id === workspace.currentUserId"
              class="inline-actions"
              aria-label="协作邀请操作"
            >
              <van-button
                size="small"
                type="primary"
                :loading="workspace.pendingAction === 'collaborator-response'"
                @click="respond('accept')"
              >
                接受协作
              </van-button>
              <van-button
                size="small"
                plain
                :loading="workspace.pendingAction === 'collaborator-response'"
                @click="respond('reject')"
              >
                拒绝
              </van-button>
            </div>
            <button
              v-else-if="canManage"
              type="button"
              class="text-action"
              :disabled="workspace.pendingAction === 'collaborator-remove'"
              @click="remove(collaborator.id)"
            >
              撤回
            </button>
          </div>
        </div>

        <div v-if="canManage && inviteCandidates.length" class="invite-row">
          <label>
            <span>邀请协作者</span>
            <select v-model="selectedUserId" aria-label="选择协作者">
              <option value="">选择项目成员</option>
              <option
                v-for="member in inviteCandidates"
                :key="member.id"
                :value="member.user_id || ''"
              >
                {{ workspace.memberName(member.user_id) }}
              </option>
            </select>
          </label>
          <van-button
            size="small"
            type="primary"
            plain
            :disabled="!selectedUserId"
            :loading="workspace.pendingAction === 'collaborator-invite'"
            @click="invite"
          >
            邀请协作者
          </van-button>
        </div>

        <van-button
          v-if="mine?.state === 'accepted'"
          size="small"
          plain
          :loading="workspace.pendingAction === 'collaborator-leave'"
          @click="leave"
        >
          退出协作
        </van-button>
      </div>
    </details>
  </section>
</template>

<style scoped>
.task-collaborators {
  border-top: 1px solid var(--tu-border);
  padding-top: 10px;
}
.responsibility-toggle {
  width: fit-content;
  cursor: pointer;
  color: var(--tu-action);
  font-weight: 600;
  padding: 8px 0;
}
.responsibility-management {
  display: grid;
  gap: 14px;
  padding: 12px 0 0;
}

.responsibility-list,
.pending-list {
  display: grid;
  gap: 0.75rem;
  margin: 0;
}

.responsibility-list > div {
  display: grid;
  grid-template-columns: minmax(5.5rem, 7rem) 1fr;
  gap: 0.75rem;
  align-items: start;
}

.responsibility-list dt {
  font-weight: 700;
}

.responsibility-list dd {
  margin: 0;
}

.people-list,
.pending-list {
  display: grid;
  gap: 0.5rem;
}

.person-row,
.invite-row,
.inline-actions,
.primary-transfer {
  display: flex;
  gap: 0.625rem;
  align-items: center;
  flex-wrap: wrap;
}

.person-row {
  justify-content: space-between;
}

.primary-transfer {
  justify-content: space-between;
  padding: 0.75rem;
  border: 1px solid var(--tu-border);
  border-radius: 10px;
}
.primary-transfer p {
  margin: 0.25rem 0 0;
}
.primary-transfer-form label {
  display: grid;
  gap: 0.35rem;
  min-width: min(100%, 18rem);
}
.primary-transfer-form select {
  min-height: 2.5rem;
}

.invite-row label {
  display: grid;
  gap: 0.35rem;
  min-width: min(100%, 18rem);
}

.invite-row select {
  min-height: 2.5rem;
}

.text-action {
  border: 0;
  background: transparent;
  color: var(--van-primary-color);
  cursor: pointer;
  padding: 0.25rem 0.4rem;
}

.text-action:disabled {
  cursor: default;
  opacity: 0.5;
}

@media (max-width: 767px) {
  .responsibility-list > div {
    grid-template-columns: 1fr;
    gap: 0.25rem;
  }

  .invite-row {
    align-items: stretch;
  }

  .invite-row label {
    width: 100%;
  }
}
</style>
