<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import { showConfirmDialog, showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import NotificationFilters from "@/components/notification/NotificationFilters.vue";
import NotificationList from "@/components/notification/NotificationList.vue";
import {
  notificationBelongsInFeed,
  notificationDestination,
} from "@/domain/notification-feed";
import { useNotificationsStore } from "@/stores/notifications";
import { useProjectsStore } from "@/stores/projects";
import type { NotificationRow } from "@/types/ui";

const router = useRouter();
const notifications = useNotificationsStore();
const projects = useProjectsStore();
const mode = ref<"all" | "unread">("all");
const projectId = ref("all");
const targetError = ref<string | null>(null);
const lastDismissed = ref<NotificationRow | null>(null);
const busy = ref(false);

const projectOptions = computed(() =>
  projects.activeItems.map(({ project }) => ({
    id: project.id,
    name: project.name,
  })),
);

const projectNames = computed<Record<string, string>>(() =>
  Object.fromEntries(
    projects.items.map(({ project }) => [project.id, project.name]),
  ),
);

const visible = computed(() =>
  notifications.items.filter((item) => {
    if (!notificationBelongsInFeed(item)) return false;
    if (mode.value === "unread" && item.read_at) return false;
    if (projectId.value === "system" && item.project_id !== null) return false;
    if (
      projectId.value !== "all" &&
      projectId.value !== "system" &&
      item.project_id !== projectId.value
    )
      return false;
    return true;
  }),
);

async function load() {
  targetError.value = null;
  await Promise.all([notifications.load(true), projects.load()]);
}

async function markAllRead() {
  try {
    await notifications.markAllRead();
  } catch {
    showToast("标记全部已读失败，请重试");
  }
}

async function dismissNotification(item: NotificationRow) {
  if (busy.value) return;
  busy.value = true;
  try {
    if (!(await notifications.dismiss(item.id))) throw new Error("NOT_FOUND");
    lastDismissed.value = item;
  } catch {
    showToast("删除通知失败，请重试");
  } finally {
    busy.value = false;
  }
}

async function undoDismiss() {
  if (!lastDismissed.value || busy.value) return;
  busy.value = true;
  try {
    if (!(await notifications.restore(lastDismissed.value.id)))
      throw new Error("RESTORE_UNAVAILABLE");
    lastDismissed.value = null;
  } catch {
    showToast("撤销失败，请刷新通知列表");
  } finally {
    busy.value = false;
  }
}

async function clearRead() {
  if (busy.value) return;
  try {
    await showConfirmDialog({
      title: "清除已读通知？",
      message: "仅从自己的通知列表隐藏已读消息；任务事件及审计记录不会删除。",
      confirmButtonText: "清除已读",
      cancelButtonText: "取消",
    });
  } catch {
    return;
  }
  busy.value = true;
  try {
    const count = await notifications.dismissRead();
    lastDismissed.value = null;
    showToast(count > 0 ? "已清除已读通知" : "暂无已读通知");
  } catch {
    showToast("清除已读通知失败");
  } finally {
    busy.value = false;
  }
}
async function openNotification(item: NotificationRow) {
  targetError.value = null;
  if (!item.read_at) {
    try {
      await notifications.markRead(item.id);
    } catch {
      showToast("已打开通知，但已读状态同步失败");
    }
  }

  try {
    const target = await notifications.resolveTarget(item.id);
    if (!target) {
      targetError.value = "关联内容不存在，或你已没有访问权限。";
      return;
    }

    const destination = notificationDestination(item, target);
    if (destination.kind === "global") {
      await router.push({ name: destination.routeName });
      return;
    }

    if (!destination.projectId) {
      targetError.value = "关联内容不存在，或你已没有访问权限。";
      return;
    }

    if (destination.routeName === "task-detail" && destination.entityId) {
      await router.push({
        name: "task-detail",
        params: {
          projectId: destination.projectId,
          taskId: destination.entityId,
        },
        query: destination.query,
      });
      return;
    }

    if (destination.routeName === "review-detail" && destination.entityId) {
      await router.push({
        name: "review-detail",
        params: {
          projectId: destination.projectId,
          reviewRoundId: destination.entityId,
        },
        query: destination.query,
      });
      return;
    }

    await router.push({
      name: destination.routeName,
      params: { projectId: destination.projectId },
      query: destination.query,
    });
  } catch {
    targetError.value = "关联内容不存在，或你已没有访问权限。";
  }
}

onMounted(() => void load());
</script>

<template>
  <div class="xiaozhuwork-page notifications-page">
    <header class="page-heading">
      <div>
        <h1>通知</h1>
      </div>
      <div class="notification-head-actions">
        <van-button
          v-if="notifications.unreadCount > 0"
          plain
          type="primary"
          @click="markAllRead"
        >
          全部标为已读
        </van-button>
        <van-button
          plain
          :disabled="
            busy || !notifications.items.some((item) => !!item.read_at)
          "
          @click="clearRead"
          >清除已读</van-button
        >
      </div>
    </header>

    <div v-if="lastDismissed" class="notification-undo" role="status">
      <span>已从个人通知列表移除“{{ lastDismissed.title }}”。</span>
      <button type="button" :disabled="busy" @click="undoDismiss">撤销</button>
    </div>
    <NotificationFilters
      v-model:mode="mode"
      v-model:project-id="projectId"
      :projects="projectOptions"
    />

    <p v-if="targetError" class="error-banner" role="status">
      {{ targetError }}
    </p>

    <PageState
      :loading="notifications.loading"
      :error="notifications.error"
      :empty="!visible.length"
      empty-title="暂无符合条件的通知"
      @retry="load"
    >
      <NotificationList
        :items="visible"
        :project-names="projectNames"
        @open="openNotification"
        @dismiss="dismissNotification"
      />
    </PageState>
  </div>
</template>

<style scoped>
.notifications-page {
  width: 100%;
  max-width: none;
}
.notification-head-actions {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.notification-undo {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  align-items: center;
  gap: 10px;
  margin-bottom: 16px;
  padding: 12px 16px;
  color: var(--tu-ink);
  background: var(--tu-subtle-surface);
  border-bottom: 1px solid var(--tu-border);
}
.notification-undo button {
  cursor: pointer;
  border: 0;
  background: transparent;
  color: var(--tu-action);
  font-weight: 650;
  padding: 8px;
}
@media (max-width: 620px) {
  .notification-head-actions {
    justify-content: flex-start;
  }
}
</style>
