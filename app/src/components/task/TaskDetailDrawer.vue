<script setup lang="ts">
import { nextTick, onBeforeUnmount, ref, watch } from "vue";
import { useRouter } from "vue-router";

import TaskDetailContent from "@/components/task/TaskDetailContent.vue";
import { registerNativeBackHandler } from "@/platform/native-back";
import { useTaskNavigationStore } from "@/stores/task-navigation";

const router = useRouter();
const navigation = useTaskNavigationStore();
const copied = ref(false);
const closeButton = ref<HTMLButtonElement | null>(null);
let triggerElement: HTMLElement | null = null;
let unregisterNativeBack: (() => void) | null = null;

async function copyStableLink() {
  if (!navigation.drawerProjectId || !navigation.drawerTaskId) return;
  const href = router.resolve({
    name: "task-detail",
    params: {
      projectId: navigation.drawerProjectId,
      taskId: navigation.drawerTaskId,
    },
  }).href;
  await navigator.clipboard.writeText(
    new URL(href, window.location.origin).toString(),
  );
  copied.value = true;
}

async function close() {
  const scrollY = navigation.source?.scrollY;
  navigation.closeDrawer();
  await nextTick();
  if (typeof scrollY === "number") {
    window.scrollTo({ top: scrollY });
  }
  triggerElement?.focus();
  triggerElement = null;
}

async function openFullPage() {
  const current = navigation.consumeForFullPage();
  if (!current) return;
  navigation.closeDrawer();
  await router.push({
    name: "task-detail",
    params: { projectId: current.projectId, taskId: current.taskId },
  });
}

watch(
  () => navigation.drawerOpen,
  async (open) => {
    unregisterNativeBack?.();
    unregisterNativeBack = null;
    if (!open) return;
    if (window.innerWidth < 768) {
      void openFullPage();
      return;
    }
    unregisterNativeBack = registerNativeBackHandler(() => {
      void close();
      return true;
    }, 80);
    triggerElement =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    await nextTick();
    closeButton.value?.focus();
  },
  { immediate: true },
);

onBeforeUnmount(() => unregisterNativeBack?.());
</script>

<template>
  <van-popup
    :show="navigation.drawerOpen"
    position="right"
    :style="{ width: 'min(760px, 94vw)', height: '100%' }"
    teleport="body"
    close-on-popstate
    @click-overlay="close"
  >
    <div
      class="drawer-shell"
      role="dialog"
      aria-modal="true"
      aria-labelledby="task-drawer-title"
      @keydown.esc.stop.prevent="close"
    >
      <header class="drawer-header">
        <button
          ref="closeButton"
          type="button"
          class="plain-button"
          @click="close"
        >
          关闭
        </button>
        <strong id="task-drawer-title">任务详情</strong>
        <div class="drawer-actions">
          <button type="button" class="plain-button" @click="copyStableLink">
            {{ copied ? "已复制" : "复制链接" }}
          </button>
          <button
            type="button"
            class="plain-button primary"
            @click="openFullPage"
          >
            全页打开
          </button>
        </div>
      </header>
      <TaskDetailContent
        v-if="navigation.drawerProjectId && navigation.drawerTaskId"
        :project-id="navigation.drawerProjectId"
        :task-id="navigation.drawerTaskId"
        compact
      />
    </div>
  </van-popup>
</template>

<style scoped>
.drawer-shell {
  height: 100%;
  overflow: auto;
  background: var(--tu-bg);
}
.drawer-header {
  position: sticky;
  top: 0;
  z-index: 3;
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  min-height: 58px;
  padding: 0 16px;
  background: var(--tu-surface);
  border-bottom: 1px solid var(--tu-border);
}
.drawer-header > :last-child {
  justify-self: end;
}
.drawer-actions {
  justify-self: end;
  display: flex;
  align-items: center;
  gap: 4px;
}
.plain-button {
  border: 0;
  background: transparent;
  color: var(--tu-muted);
  cursor: pointer;
  min-height: 44px;
  padding: 0 8px;
}
.plain-button.primary {
  color: var(--tu-blue-strong);
  font-weight: 700;
}
</style>
