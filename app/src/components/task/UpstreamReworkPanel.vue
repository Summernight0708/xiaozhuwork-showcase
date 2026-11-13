<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { showToast } from "vant";

import { useTaskWorkflowStore } from "@/stores/task-workflow";
import { useWorkspaceStore } from "@/stores/workspace";
import type { UpstreamReworkRequestRow } from "@/services/task-workflow-repository";

const props = defineProps<{ projectId: string; taskId: string }>();

const workspace = useWorkspaceStore();
const workflow = useTaskWorkflowStore();
const selectedUpstreamTaskId = ref("");
const requirement = ref("");

const task = computed(() => workspace.findTask(props.taskId));
const upstreamTasks = computed(() => workspace.upstreamTasks(props.taskId));
const completedUpstreamTasks = computed(() =>
  upstreamTasks.value.filter((upstream) => upstream.status === "completed"),
);
const canRequestRework = computed(
  () =>
    !!task.value &&
    workspace.role !== "observer" &&
    (workspace.role === "leader" ||
      ((workspace.isTaskParticipant?.(task.value) ??
        task.value.assignee_id === workspace.currentUserId) &&
        task.value.assignment_state === "assigned")),
);
const pendingRequests = computed(() =>
  workflow.reworkRequests.filter((request) => request.state === "pending"),
);

watch(
  completedUpstreamTasks,
  (tasks) => {
    if (
      !selectedUpstreamTaskId.value ||
      !tasks.some((task) => task.id === selectedUpstreamTaskId.value)
    ) {
      selectedUpstreamTaskId.value = tasks[0]?.id ?? "";
    }
  },
  { immediate: true },
);

async function requestRework() {
  if (
    !task.value ||
    !selectedUpstreamTaskId.value ||
    !requirement.value.trim()
  ) {
    showToast("请选择已完成的直接上游并填写返工要求");
    return;
  }
  const upstream = completedUpstreamTasks.value.find(
    (candidate) => candidate.id === selectedUpstreamTaskId.value,
  );
  if (!upstream) {
    showToast("所选上游已不再可返工，请刷新后重试");
    return;
  }
  const result = await workflow.requestRework(
    task.value,
    upstream,
    requirement.value.trim(),
  );
  if (result.ok) {
    requirement.value = "";
    showToast(
      result.data.state === "approved" ? "已直接发起返工" : "返工申请已提交",
    );
  } else {
    showToast(workflow.actionError || "返工申请失败");
  }
}

async function reviewRequest(
  request: UpstreamReworkRequestRow,
  action: "approve" | "reject",
) {
  const result = await workflow.reviewRework(request, action);
  if (result.ok) {
    showToast(action === "approve" ? "已批准返工" : "已拒绝返工");
  } else {
    showToast(workflow.actionError || "处理返工申请失败");
  }
}

function stateLabel(state: UpstreamReworkRequestRow["state"]) {
  if (state === "approved") return "已批准";
  if (state === "rejected") return "已拒绝";
  return "待组长处理";
}
</script>

<template>
  <section class="workflow-panel">
    <div class="panel-heading">
      <div>
        <h2>上游返工</h2>
        <p>仅针对当前任务的直接上游；已完成下游不会被历史回滚。</p>
      </div>
      <span v-if="pendingRequests.length" class="count-pill">
        {{ pendingRequests.length }} 条待处理
      </span>
    </div>

    <div
      v-if="canRequestRework && completedUpstreamTasks.length"
      class="request-form"
    >
      <label>
        <span>已完成的直接上游</span>
        <select v-model="selectedUpstreamTaskId">
          <option
            v-for="upstream in completedUpstreamTasks"
            :key="upstream.id"
            :value="upstream.id"
          >
            {{ upstream.title }}
          </option>
        </select>
      </label>
      <label>
        <span>返工要求</span>
        <textarea
          v-model="requirement"
          rows="3"
          maxlength="2000"
          placeholder="说明需要上游补充或修改的内容"
        />
      </label>
      <p v-if="workspace.role === 'leader'" class="hint">
        组长提交后将直接批准并重新打开该上游任务。
      </p>
      <van-button
        size="small"
        type="primary"
        :loading="
          workflow.pendingAction === `request-rework:${selectedUpstreamTaskId}`
        "
        :disabled="!!workflow.pendingAction"
        @click="requestRework"
      >
        {{ workspace.role === "leader" ? "直接返工" : "申请上游返工" }}
      </van-button>
    </div>
    <p v-else-if="canRequestRework" class="hint">
      当前没有已完成的直接上游可申请返工。
    </p>
    <p v-else class="hint">
      当前任务主负责人或已接受协作者可以申请返工；组长可直接执行返工。
    </p>

    <p v-if="workflow.error || workflow.actionError" class="error-note">
      {{ workflow.error || workflow.actionError }}
    </p>

    <div v-if="workflow.reworkRequests.length" class="history-list">
      <article
        v-for="request in workflow.reworkRequests"
        :key="request.id"
        class="history-card"
      >
        <div class="history-title">
          <strong>{{ stateLabel(request.state) }}</strong>
          <span>{{ new Date(request.created_at).toLocaleString() }}</span>
        </div>
        <p>{{ request.requirement }}</p>
        <p class="meta">
          下游：{{
            workspace.findTask(request.downstream_task_id)?.title || "任务"
          }}
          · 上游：{{
            workspace.findTask(request.upstream_task_id)?.title || "任务"
          }}
          · 发起：{{ workspace.memberName(request.requested_by) }}
        </p>
        <div
          v-if="workspace.role === 'leader' && request.state === 'pending'"
          class="review-actions"
        >
          <van-button
            size="small"
            type="primary"
            :loading="workflow.pendingAction === `review-rework:${request.id}`"
            :disabled="!!workflow.pendingAction"
            @click="reviewRequest(request, 'approve')"
          >
            批准返工
          </van-button>
          <van-button
            size="small"
            plain
            type="danger"
            :loading="workflow.pendingAction === `review-rework:${request.id}`"
            :disabled="!!workflow.pendingAction"
            @click="reviewRequest(request, 'reject')"
          >
            拒绝
          </van-button>
        </div>
      </article>
    </div>
    <p v-else-if="!workflow.loading" class="hint">暂无返工记录。</p>
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
.request-form label {
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
.review-actions {
  display: flex;
  gap: 8px;
  margin-top: 10px;
}
.error-note {
  color: var(--tu-danger);
  margin: 0;
}
</style>
