<script setup lang="ts">
import { computed } from "vue";
import type { ProjectRole } from "@/domain/access-control";

const props = defineProps<{
  role: ProjectRole;
  memberCount: number;
  taskCount: number;
  projectId: string;
  archived: boolean;
  syncError: boolean;
}>();
const emit = defineEmits<{ dismiss: [] }>();
const title = computed(
  () =>
    ({
      leader: "组长入门",
      admin: "管理员入门",
      member: "成员入门",
      observer: "观察者入门",
    })[props.role],
);
const steps = computed(() => {
  if (props.role === "leader")
    return [
      {
        label: "邀请同学",
        done: props.memberCount > 1,
        to: "project-invitations",
      },
      {
        label: "创建任务并分工",
        done: props.taskCount > 0,
        to: "project-tasks",
      },
      { label: "了解验收和贡献报告", done: false, to: "project-reviews" },
    ];
  if (props.role === "admin")
    return [
      {
        label: "查看任务和分工",
        done: props.taskCount > 0,
        to: "project-tasks",
      },
      { label: "帮助成员推进协作", done: false, to: "project-todos" },
      { label: "理解验收职责", done: false, to: "project-reviews" },
    ];
  if (props.role === "member")
    return [
      { label: "查看我的工作", done: props.taskCount > 0, to: "project-todos" },
      { label: "了解依赖和成果提交", done: false, to: "project-tasks" },
      { label: "查看贡献记录", done: false, to: "project-contributions" },
    ];
  return [
    {
      label: "阅读项目任务流程",
      done: props.taskCount > 0,
      to: "project-tasks",
    },
    { label: "了解项目文件", done: false, to: "project-files" },
    { label: "了解只读权限边界", done: false, to: "project-members" },
  ];
});
</script>

<template>
  <section class="surface intro-card" aria-label="新手入门">
    <div class="intro-header">
      <div>
        <p class="intro-eyebrow">第一次以当前角色进入项目</p>
        <h2>{{ title }}</h2>
        <p>按自己的角色学习使用小猪作业；这些步骤不会替你修改项目。</p>
      </div>
      <button type="button" class="intro-dismiss" @click="emit('dismiss')">
        关闭引导 ×
      </button>
    </div>
    <ol class="intro-steps">
      <li v-for="step in steps" :key="step.label">
        <span
          class="intro-status"
          :aria-label="step.done ? '已具备相关项目数据' : '可查看'"
          >{{ step.done ? "✓" : "·" }}</span
        >
        <RouterLink :to="{ name: step.to, params: { projectId } }"
          >{{ step.label }} →</RouterLink
        >
      </li>
    </ol>
    <div class="intro-footer">
      <RouterLink :to="{ name: 'help-center' }"
        >前往使用帮助阅读完整教程</RouterLink
      >
      <small v-if="archived">当前项目已归档，部分操作仅可查看。</small>
      <small v-if="syncError" role="status"
        >关闭状态暂未跨设备同步，可稍后再试。</small
      >
    </div>
  </section>
</template>

<style scoped>
.intro-card {
  padding: 22px;
  border: 1px solid var(--tu-border);
  border-radius: 15px;
  margin: 16px 0 20px;
}
.intro-header {
  display: flex;
  justify-content: space-between;
  align-items: start;
  gap: 16px;
}
.intro-header h2 {
  margin: 5px 0;
  font-size: 21px;
}
.intro-header p {
  margin: 5px 0;
  line-height: 1.5;
  color: var(--tu-muted);
  font-size: 14px;
}
.intro-eyebrow {
  font-weight: 700;
  font-size: 12px !important;
}
.intro-dismiss {
  flex-shrink: 0;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  padding: 8px 10px;
  color: var(--tu-ink);
  background: var(--tu-bg);
  cursor: pointer;
}
.intro-steps {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  padding: 0;
  list-style: none;
}
.intro-steps li {
  display: flex;
  align-items: center;
  gap: 8px;
  border: 1px solid var(--tu-border);
  border-radius: 10px;
  padding: 12px;
  font-size: 14px;
}
.intro-status {
  font-weight: 700;
  color: var(--tu-success);
}
.intro-footer {
  display: flex;
  flex-wrap: wrap;
  gap: 14px;
  margin-top: 12px;
  align-items: center;
}
.intro-footer a {
  text-decoration: underline;
  text-underline-offset: 3px;
}
.intro-footer small {
  color: var(--tu-muted);
}
@media (max-width: 650px) {
  .intro-header {
    flex-direction: column;
  }
  .intro-steps {
    flex-direction: column;
  }
}
</style>
