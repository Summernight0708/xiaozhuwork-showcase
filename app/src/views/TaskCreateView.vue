<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import TaskForm from "@/components/task/TaskForm.vue";
import TaskReferenceFilePicker from "@/components/task/TaskReferenceFilePicker.vue";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import {
  emptyTaskForm,
  validateTaskForm,
  type TaskFormCapabilities,
} from "@/domain/task-form";

const router = useRouter();
const { workspace, projectId, reload } = useWorkspaceRoute();
const model = ref(emptyTaskForm());
const referenceFiles = ref<File[]>([]);
const submitting = ref(false);

const capabilities: TaskFormCapabilities = {
  startAt: false,
  collaborators: true,
  requiredFileType: true,
};

async function cancel() {
  await router.push({
    name: "project-tasks",
    params: { projectId: projectId.value },
  });
}

async function create() {
  const validationError = validateTaskForm(model.value, capabilities, {
    projectDeadlineAt: workspace.project?.deadline_at,
  });
  if (validationError) {
    showToast(validationError);
    return;
  }
  if (Date.parse(model.value.deadlineAt) <= Date.now()) {
    showToast("截止时间必须晚于当前时间");
    return;
  }

  submitting.value = true;
  try {
    await reload();
    if (
      !workspace.project ||
      !workspace.membership ||
      !workspace.capabilities.canCreateTask
    ) {
      showToast("你当前没有在此项目创建任务的权限，成员身份可能已变化。");
      return;
    }
    if (workspace.project.lifecycle_state !== "active") {
      showToast("项目状态已变化，当前不能再创建任务。");
      return;
    }
    if (
      Date.parse(model.value.deadlineAt) >
      Date.parse(workspace.project.deadline_at)
    ) {
      showToast(
        `任务截止时间不能晚于项目 DDL（${new Date(
          workspace.project.deadline_at,
        ).toLocaleString()}）`,
      );
      return;
    }

    const result = await workspace.createTask({
      title: model.value.title.trim(),
      description: model.value.description.trim() || undefined,
      deadlineAt: new Date(model.value.deadlineAt).toISOString(),
      weight:
        workspace.project.contribution_mode === "facts_only"
          ? undefined
          : model.value.difficulty,
      assignmentMode: model.value.assignmentMode,
      assigneeId:
        model.value.assignmentMode === "direct"
          ? model.value.assigneeId
          : undefined,
      requiredSubmissionFileTypes: model.value.requiredFileTypes,
      requiresReview: model.value.requiresReview,
    });
    if (!result.ok) {
      showToast(workspace.actionError || "创建任务失败");
      return;
    }

    const createdTask = workspace.findTask(result.data.taskId);
    if (!createdTask) {
      showToast("任务已创建，但无法加载后续设置");
      return;
    }

    if (model.value.upstreamTaskIds.length) {
      const dependencyResult = await workspace.setTaskDependencies(
        createdTask,
        model.value.upstreamTaskIds,
      );
      if (!dependencyResult.ok) {
        showToast(workspace.actionError || "任务已创建，但上游任务设置失败");
        return;
      }
    }

    for (const collaboratorId of model.value.collaboratorIds) {
      const collaboratorResult = await workspace.inviteTaskCollaborator(
        createdTask,
        collaboratorId,
      );
      if (!collaboratorResult.ok) {
        showToast(
          workspace.actionError || "任务已创建，但协作者邀请未全部完成",
        );
        return;
      }
    }

    let referenceUploadFailed = false;
    for (const file of referenceFiles.value) {
      const currentTask = workspace.findTask(result.data.taskId) ?? createdTask;
      const uploadResult = await workspace.uploadFile(
        currentTask,
        file,
        "new_file",
      );
      if (!uploadResult.ok) {
        referenceUploadFailed = true;
        break;
      }
      const markResult = await workspace.markTaskFileReference(
        currentTask,
        uploadResult.data.fileId,
        1,
      );
      if (!markResult.ok) {
        referenceUploadFailed = true;
        break;
      }
    }

    showToast(
      referenceUploadFailed
        ? "任务已创建，但有任务资料上传失败，请在任务详情确认。"
        : "任务已创建",
    );
    await router.replace({
      name: "task-detail",
      params: { projectId: projectId.value, taskId: result.data.taskId },
    });
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <div class="xiaozhuwork-page form-page">
    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="!workspace.project || !workspace.membership"
      :permission-denied="
        !!workspace.membership && !workspace.capabilities.canCreateTask
      "
      @retry="reload"
    >
      <template v-if="workspace.capabilities.canCreateTask">
        <header class="page-heading">
          <div>
            <h1>创建任务</h1>
            <p>基本信息、责任与时间、工作流与提交集中在一页完成。</p>
          </div>
        </header>

        <TaskForm
          v-model="model"
          :members="workspace.members"
          :tasks="workspace.tasks"
          :capabilities="capabilities"
          :contribution-mode="workspace.project?.contribution_mode"
          :project-deadline-at="workspace.project?.deadline_at"
          :submitting="submitting"
          submit-label="创建任务"
          @submit="create"
          @cancel="cancel"
        >
          <template #creation-extras>
            <TaskReferenceFilePicker v-model="referenceFiles" />
          </template>
        </TaskForm>
      </template>
    </PageState>
  </div>
</template>

<style scoped>
.form-page {
  width: 100%;
  max-width: none;
}
</style>
