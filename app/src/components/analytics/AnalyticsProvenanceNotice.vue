<script setup lang="ts">
import type { ProjectAnalytics } from "@/services/project-analytics";

defineProps<{ analytics: ProjectAnalytics }>();
</script>

<template>
  <aside class="provenance-notice" aria-label="数据口径说明">
    <strong>数据口径</strong>
    <p>
      本页基于当前保留任务行、持久化创建/完成时间和直接依赖关系；不是历史状态回放，
      不包含已删除任务，也不包含协作者贡献推断。项目时区
      {{ analytics.projectTimezone }} 仅作项目元数据，趋势始终按 UTC 分桶。
    </p>
    <p v-if="analytics.dataIssues.completedMissingTime > 0">
      有 {{ analytics.dataIssues.completedMissingTime }}
      项当前已完成任务缺少完成时间，未进入窗口完成与用时样本。
    </p>
  </aside>
</template>

<style scoped>
.provenance-notice {
  padding: 14px 16px;
  border: 1px solid #dfd4c8;
  border-radius: 12px;
  background: #f8f3ed;
  color: #654f3f;
}

strong {
  display: block;
  font-size: 12px;
}

p {
  margin: 4px 0 0;
  font-size: 12px;
  line-height: 1.65;
}

html[data-theme="dark"] .provenance-notice {
  border-color: #4a4038;
  background: #2b2723;
  color: #d9c8b8;
}
</style>
