<script setup lang="ts">
import { computed, ref } from "vue";
import { showToast } from "vant";

import { useTaskWorkflowStore } from "@/stores/task-workflow";
import { useWorkspaceStore } from "@/stores/workspace";
import type { TaskHelpRequestRow } from "@/services/task-workflow-repository";

const props = defineProps<{ projectId: string; taskId: string }>();

const workspace = useWorkspaceStore();
const workflow = useTaskWorkflowStore();
const message = ref("");
const targetUserId = ref("");
const marksTaskBlocked = ref(false);

const task = computed(() => workspace.findTask(props.taskId));
const canRequestHelp = computed(
  () =>
    !!task.value &&
    workspace.role !== "observer" &&
    (workspace.isTaskParticipant?.(task.value) ??
      task.value.assignee_id === workspace.currentUserId) &&
    task.value.assignment_state === "assigned" &&
    ["not_started", "in_progress", "blocked"].includes(task.value.status),
);
const helperOptions = computed(() =>
  workspace.members.flatMap((member) =>
    member.member_state === "active" &&
    member.role !== "observer" &&
    member.user_id
      ? [{ ...member, user_id: member.user_id }]
      : [],
  ),
);
const openHelpRequests = computed(() =>
  workflow.helpRequests.filter((request) => request.state === "open"),
);

function canResolve(request: TaskHelpRequestRow) {
  if (request.state !== "open") return false;
  return (
    workspace.role === "leader" ||
    request.requested_by === workspace.currentUserId ||
    request.target_user_id === workspace.currentUserId
  );
}

async function createHelp() {
  if (!task.value || !message.value.trim()) {
    showToast("请填写求助内容");
    return;
  }
  const result = await workflow.createHelp(task.value, {
    message: message.value.trim(),
    targetUserId: targetUserId.value || undefined,
    marksTaskBlocked: marksTaskBlocked.value,
  });
  if (result.ok) {
    message.value = "";
    marksTaskBlocked.value = false;
    showToast("求助已发出");
  } else {
    showToast(workflow.actionError || "求助失败");
  }
}

async function resolveHelp(request: TaskHelpRequestRow) {
  const result = await workflow.resolveHelp(request);
  if (result.ok) {
    showToast(
      result.data.taskResumed
        ? "求助已解决，任务已恢复进行"
        : "求助已解决；当前阻塞状态保留，请按任务现状手动处理",
    );
  } else {
    showToast(workflow.actionError || "解决求助失败");
  }
}
</script>

<template>
  <section class="workflow-panel">
    <div class="panel-heading">
      <div>
        <h2>任务求助</h2>
        <p>向项目成员请求协助；需要时可让当前任务进入阻塞。</p>
      </div>
      <span v-if="openHelpRequests.length" class="count-pill">
        {{ openHelpRequests.length }} 条待解决
      </span>
    </div>

    <div v-if="canRequestHelp" class="request-form">
      <label>
        <span>求助人</span>
        <select v-model="targetUserId">
          <option value="">默认通知组长</option>
          <option
            v-for="member in helperOptions"
            :key="member.user_id"
            :value="member.user_id"
          >
            {{ workspace.memberName(member.user_id) }}
          </option>
        </select>
      </label>
      <label class="wide">
        <span>求助内容</span>
        <textarea
          v-model="message"
          rows="3"
          maxlength="2000"
          placeholder="说明遇到的问题、希望获得什么帮助"
        />
      </label>
      <label class="block-toggle">
        <input v-model="marksTaskBlocked" type="checkbox" />
        <span>同时将任务标记为阻塞</span>
      </label>
      <p v-if="task?.status === 'blocked'" class="hint">
        当前任务已经处于手动阻塞状态；数据库不会允许新求助覆盖现有阻塞原因。
      </p>
      <van-button
        size="small"
        type="primary"
        :loading="workflow.pendingAction === 'create-help'"
        :disabled="!!workflow.pendingAction"
        @click="createHelp"
      >
        发起求助
      </van-button>
    </div>
    <p v-else class="hint">
      只有当前任务的主负责人或已接受协作者可以发起求助。
    </p>

    <p v-if="workflow.error || workflow.actionError" class="error-note">
      {{ workflow.error || workflow.actionError }}
    </p>

    <div v-if="workflow.helpRequests.length" class="history-list">
      <article
        v-for="request in workflow.helpRequests"
        :key="request.id"
        class="history-card"
      >
        <div class="history-title">
          <strong>
            {{ request.state === "open" ? "待解决" : "已解决" }}
          </strong>
          <span>{{ new Date(request.created_at).toLocaleString() }}</span>
        </div>
        <p>{{ request.message }}</p>
        <p class="meta">
          发起：{{ workspace.memberName(request.requested_by) }} · 求助：
          {{ workspace.memberName(request.target_user_id) }}
          <template v-if="request.marks_task_blocked"> · 请求阻塞任务</template>
        </p>
        <van-button
          v-if="canResolve(request)"
          size="small"
          plain
          type="primary"
          :loading="workflow.pendingAction === `resolve-help:${request.id}`"
          :disabled="!!workflow.pendingAction"
          @click="resolveHelp(request)"
        >
          标记已解决
        </van-button>
      </article>
    </div>
    <p v-else-if="!workflow.loading" class="hint">暂无求助记录。</p>
  </section>
</template>

<style scoped>
.workflow-panel {
  display: grid;
  gap: 14px;
}
.panel-heading,
.history-title {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: flex-start;
}
.panel-heading h2 {
  margin: 0;
  font-size: 18px;
}
.panel-heading p,
.history-card p {
  margin: 5px 0 0;
}
.count-pill {
  white-space: nowrap;
  font-size: 12px;
  padding: 4px 8px;
  border-radius: 999px;
  background: var(--tu-subtle-surface);
}
.request-form {
  display: grid;
  gap: 10px;
}
.request-form label:not(.block-toggle) {
  display: grid;
  gap: 6px;
}
.request-form select,
.request-form textarea {
  width: 100%;
  box-sizing: border-box;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  padding: 9px 10px;
  background: transparent;
  color: inherit;
}
.block-toggle {
  display: flex;
  gap: 8px;
  align-items: center;
}
.history-list {
  display: grid;
  gap: 10px;
}
.history-card {
  border: 1px solid var(--tu-border);
  border-radius: 10px;
  padding: 12px;
}
.history-title span,
.meta,
.hint {
  color: var(--tu-muted);
  font-size: 13px;
}
.error-note {
  color: var(--tu-danger);
  margin: 0;
}
</style>
