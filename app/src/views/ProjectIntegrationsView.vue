<script setup lang="ts">
import { computed } from "vue";
import CalendarSubscriptionManager from "@/components/integrations/CalendarSubscriptionManager.vue";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";

const { workspace, projectId } = useWorkspaceRoute();
const leader = computed(
  () =>
    workspace.membership?.member_state === "active" &&
    workspace.membership?.role === "leader",
);
const state = computed(() => workspace.entitlement?.state ?? "free");
</script>

<template>
  <main class="integrations-view">
    <h1>外部日历订阅</h1>
    <p>
      将项目未来任务截止时间添加到支持 iCalendar
      的日历客户端。此功能为只读，不会修改任务。
    </p>
    <CalendarSubscriptionManager
      v-if="workspace.project && projectId"
      :project-id="projectId"
      :leader="leader"
      :entitlement-state="state"
    />
    <p v-else>项目正在加载，或当前账户无权查看。</p>
  </main>
</template>

<style scoped>
.integrations-view {
  margin: 0 auto;
  padding: 1rem;
}
.integrations-view h1 {
  font-size: 1.5rem;
}
</style>
