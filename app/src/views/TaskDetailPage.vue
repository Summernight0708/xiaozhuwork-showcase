<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";

import TaskDetailContent from "@/components/task/TaskDetailContent.vue";
import {
  hasSafeInAppHistoryBack,
  projectBackTarget,
} from "@/domain/project-navigation";

const route = useRoute();
const router = useRouter();
const projectId = computed(() => String(route.params.projectId));
const taskId = computed(() => String(route.params.taskId));

async function goBack() {
  if (hasSafeInAppHistoryBack(router.options.history.state.back)) {
    router.back();
    return;
  }

  const fallback = projectBackTarget(route.name);
  await router.replace({
    name: fallback?.routeName ?? "project-tasks",
    params: { projectId: projectId.value },
  });
}
</script>

<template>
  <div class="xiaozhuwork-page task-page">
    <button type="button" class="back-button" @click="goBack">
      ← 返回任务列表
    </button>
    <TaskDetailContent :project-id="projectId" :task-id="taskId" />
  </div>
</template>

<style scoped>
.task-page {
  padding-top: 18px;
}
.back-button {
  min-height: 42px;
  margin-bottom: 8px;
  border: 0;
  background: transparent;
  color: var(--tu-blue-strong);
  cursor: pointer;
  font-weight: 700;
}
</style>
