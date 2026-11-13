<script setup lang="ts">
import type { CrossProject } from "@/services/cross-project";

defineProps<{
  projects: CrossProject[];
  selectedIds: string[];
  includeAll: boolean;
  loading: boolean;
  hasNext: boolean;
}>();
const emit = defineEmits<{
  toggle: [projectId: string];
  more: [];
}>();

const stateLabel: Record<CrossProject["lifecycleState"], string> = {
  active: "进行中",
  contribution_review: "贡献确认中",
  completed: "已完成",
};
</script>

<template>
  <section aria-label="可访问的项目" class="project-list">
    <div v-if="!projects.length && !loading" class="empty">
      没有符合条件的项目，或当前没有可访问的项目。
    </div>
    <div
      v-for="project in projects"
      :key="project.projectId"
      class="project-item"
    >
      <label class="selection">
        <input
          type="checkbox"
          :checked="includeAll || selectedIds.includes(project.projectId)"
          :aria-label="'选择 ' + project.name"
          @change="emit('toggle', project.projectId)"
        />
      </label>
      <div class="project-copy">
        <RouterLink
          class="project-name"
          :to="{
            name: 'project-overview',
            params: { projectId: project.projectId },
          }"
          >{{ project.name }}</RouterLink
        >
        <p>{{ project.courseName || "未设置课程" }} · {{ project.timezone }}</p>
        <small
          >截止：{{
            project.deadlineAt
              ? new Date(project.deadlineAt).toLocaleDateString()
              : "未设置"
          }}</small
        >
      </div>
      <span class="state">{{ stateLabel[project.lifecycleState] }}</span>
    </div>
    <button
      v-if="hasNext"
      class="secondary"
      :disabled="loading"
      type="button"
      @click="emit('more')"
    >
      {{ loading ? "加载中…" : "加载更多项目" }}
    </button>
  </section>
</template>

<style scoped>
.project-list {
  display: grid;
  gap: 0;
  border-top: 1px solid var(--tu-border);
}
.project-item {
  background: transparent;
  border-bottom: 1px solid var(--tu-border);
  padding: var(--space-md) 0;
  display: flex;
  align-items: flex-start;
  gap: 14px;
}
.project-copy {
  min-width: 0;
  flex: 1;
  overflow-wrap: anywhere;
}
.project-name {
  color: var(--tu-action);
  font-weight: 700;
}
.project-copy p {
  margin: 5px 0;
  color: var(--tu-muted);
}
.project-copy small {
  color: var(--tu-muted);
}
.selection {
  padding-top: 3px;
}
.selection input {
  width: 19px;
  height: 19px;
}
.state {
  padding: 4px 0;
  font-size: 12px;
  color: var(--tu-blue-strong);
  white-space: nowrap;
}
.secondary {
  justify-self: start;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  padding: 10px 16px;
  background: var(--tu-surface);
  cursor: pointer;
}
.empty {
  padding: var(--space-xl) 0;
  color: var(--tu-muted);
}
@media (max-width: 540px) {
  .project-item {
    padding: 12px;
    gap: 10px;
  }
  .state {
    white-space: normal;
    text-align: center;
  }
}
</style>
