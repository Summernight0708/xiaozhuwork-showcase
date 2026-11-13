<script setup lang="ts">
defineOptions({ name: "ProjectsView" });

import { computed, onActivated, onMounted, ref } from "vue";

import PageState from "@/components/common/PageState.vue";
import { ROLE_LABELS } from "@/domain/access-control";
import type { ProjectSummary } from "@/types/ui";
import { useProjectsStore } from "@/stores/projects";

const projects = useProjectsStore();
const search = ref("");
const scope = ref<"all" | "leader" | "participant" | "archived">("all");

const filtered = computed(() => {
  const keyword = search.value.trim().toLowerCase();
  return projects.items.filter((item) => {
    const matchesKeyword =
      !keyword ||
      item.project.name.toLowerCase().includes(keyword) ||
      (item.project.course_name ?? "").toLowerCase().includes(keyword);
    const matchesScope =
      scope.value === "all" ||
      (scope.value === "leader" && item.role === "leader") ||
      (scope.value === "participant" &&
        item.role !== "leader" &&
        !item.project.archived_at) ||
      (scope.value === "archived" && !!item.project.archived_at);
    return matchesKeyword && matchesScope;
  });
});

function deadlineStatus(item: ProjectSummary) {
  if (item.project.archived_at) return { label: "已归档", overdue: false };
  if (item.project.lifecycle_state === "completed")
    return { label: "已完成", overdue: false };
  if (item.project.lifecycle_state === "contribution_review")
    return { label: "待贡献确认", overdue: false };

  const diff = Date.parse(item.project.deadline_at) - Date.now();
  if (diff < 0) {
    const overdue = item.role === "leader" || item.myOpenTaskCount > 0;
    return {
      label: overdue ? "已超过项目 DDL" : "项目 DDL 已结束",
      overdue,
    };
  }
  const days = Math.ceil(diff / 86_400_000);
  return {
    label: days <= 1 ? "24 小时内到期" : `剩余 ${days} 天`,
    overdue: false,
  };
}

onMounted(() => void projects.load());
onActivated(() => void projects.load());
</script>

<template>
  <div class="xiaozhuwork-page">
    <header class="page-heading">
      <div>
        <h1>我的项目</h1>
      </div>
      <RouterLink to="/projects/create"
        ><van-button type="primary">创建项目</van-button></RouterLink
      >
    </header>

    <div class="toolbar">
      <van-search v-model="search" class="grow" placeholder="搜索项目或课程" />
      <div class="scope-tabs" aria-label="项目范围">
        <button
          v-for="option in [
            ['all', '全部'],
            ['leader', '我负责'],
            ['participant', '我参与'],
            ['archived', '已归档'],
          ]"
          :key="option[0]"
          type="button"
          :class="{ active: scope === option[0] }"
          @click="scope = option[0] as typeof scope"
        >
          {{ option[1] }}
        </button>
      </div>
    </div>

    <PageState
      :loading="projects.loading"
      :error="projects.error"
      :empty="!filtered.length"
      empty-title="暂时没有符合条件的项目"
      @retry="projects.load(true)"
    >
      <div class="project-grid">
        <RouterLink
          v-for="item in filtered"
          :key="item.project.id"
          class="project-card"
          :to="{
            name: 'project-overview',
            params: { projectId: item.project.id },
          }"
        >
          <div class="project-card-head">
            <div>
              <span class="role">{{ ROLE_LABELS[item.role] }}</span>
              <h2>{{ item.project.name }}</h2>
              <p>{{ item.project.course_name || "未设置课程" }}</p>
            </div>
            <span
              class="deadline"
              :class="{ overdue: deadlineStatus(item).overdue }"
            >
              {{ deadlineStatus(item).label }}
            </span>
          </div>
          <div class="facts">
            <span
              ><b>{{ item.taskCounts.inProgress }}</b
              >进行中</span
            >
            <span
              ><b>{{ item.taskCounts.blocked }}</b
              >阻塞</span
            >
            <span
              ><b>{{ item.taskCounts.pendingReview }}</b
              >待验收</span
            >
            <span
              ><b>{{ item.taskCounts.pending }}</b
              >待接受/开始</span
            >
          </div>
          <p
            v-if="item.taskCounts.blocked || item.taskCounts.pendingReview"
            class="next-step"
          >
            {{
              item.taskCounts.blocked
                ? "存在阻塞任务，建议先处理风险。"
                : "有提交正在等待验收。"
            }}
          </p>
        </RouterLink>
      </div>
    </PageState>
  </div>
</template>

<style scoped>
.scope-tabs {
  display: inline-flex;
  align-items: center;
  gap: var(--space-md);
  border-bottom: 1px solid var(--tu-border);
}
.scope-tabs button {
  min-height: 40px;
  padding: 8px 2px;
  border: 0;
  border-bottom: 2px solid transparent;
  background: transparent;
  color: var(--tu-muted);
  cursor: pointer;
}
.scope-tabs button.active {
  border-bottom-color: var(--tu-action);
  color: var(--tu-ink);
  font-weight: 650;
}
.project-grid {
  display: grid;
  gap: 0;
  border-top: 1px solid var(--tu-border);
}
.project-card {
  display: grid;
  grid-template-columns: minmax(0, 1.8fr) minmax(270px, 1fr);
  align-items: center;
  column-gap: var(--space-xl);
  row-gap: var(--space-xs);
  padding: var(--space-lg) var(--space-sm);
  border-bottom: 1px solid var(--tu-border);
  transition: background-color var(--dur-ui) var(--ease-ui);
}
.project-card:hover,
.project-card:focus-visible {
  background: var(--tu-subtle-surface);
}
.project-card-head {
  display: flex;
  justify-content: space-between;
  gap: var(--space-md);
  min-width: 0;
}
.project-card-head > div {
  min-width: 0;
}
.project-card h2 {
  margin: var(--space-2xs) 0;
  font-size: var(--text-lg);
  line-height: 1.4;
  overflow-wrap: anywhere;
}
.project-card p {
  margin: 0;
  color: var(--tu-muted);
}
.role {
  font-size: var(--text-xs);
  color: var(--tu-muted);
}
.deadline {
  align-self: center;
  white-space: nowrap;
  font-size: var(--text-sm);
  color: var(--tu-muted);
}
.deadline.overdue {
  color: var(--tu-danger);
  font-weight: 650;
}
.facts {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: var(--space-sm);
  align-items: center;
}
.facts span {
  display: flex;
  flex-direction: column;
  gap: 2px;
  color: var(--tu-muted);
  font-size: var(--text-xs);
}
.facts b {
  color: var(--tu-ink);
  font-size: var(--text-md);
  font-weight: 650;
}
.next-step {
  grid-column: 1 / -1;
  color: var(--tu-warning-ink) !important;
  font-size: var(--text-xs);
}
.toolbar :deep(.van-search) {
  padding: 0;
  background: transparent;
}
.toolbar :deep(.van-search__content) {
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  background: var(--tu-surface);
}
@media (max-width: 900px) {
  .project-card {
    grid-template-columns: 1fr;
  }
  .facts {
    justify-content: start;
    max-width: 600px;
  }
}
@media (max-width: 520px) {
  .toolbar {
    display: grid;
    gap: var(--space-xs);
  }
  .scope-tabs {
    justify-content: space-between;
    gap: var(--space-xs);
  }
  .scope-tabs button {
    font-size: var(--text-sm);
  }
  .project-card {
    padding: var(--space-md) 0;
  }
  .project-card-head {
    align-items: flex-start;
  }
  .deadline {
    align-self: start;
    font-size: var(--text-xs);
  }
  .facts {
    grid-template-columns: repeat(4, minmax(0, 1fr));
  }
}
</style>
