import { defineStore } from "pinia";
import { ref } from "vue";

import { getBackend } from "@/services/backend";
import { unknownErrorMessage } from "@/services/errors";
import { createRepository } from "@/services/repository";
import { useAuthStore } from "@/stores/auth";
import type { NotificationRow, NotificationTarget } from "@/types/ui";

export const useNotificationsStore = defineStore("notifications", () => {
  const items = ref<NotificationRow[]>([]);
  const unreadCount = ref(0);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const loaded = ref(false);
  const loadedUserId = ref<string | null>(null);
  let loadGeneration = 0;

  async function load(force = false) {
    const backend = getBackend();
    const auth = useAuthStore();
    const userId = auth.user?.id ?? null;
    if (!backend || !userId) return;

    const sameUser = loadedUserId.value === userId;
    if (loaded.value && sameUser && !force) return;

    const generation = ++loadGeneration;
    if (!sameUser) {
      loadedUserId.value = userId;
      items.value = [];
      unreadCount.value = 0;
      loaded.value = false;
    }

    loading.value = true;
    error.value = null;
    const isCurrentUser = () =>
      generation === loadGeneration && loadedUserId.value === userId;

    try {
      const repository = createRepository(backend.client);
      const [nextItems, nextUnreadCount] = await Promise.all([
        repository.listNotifications(),
        repository.getUnreadNotificationCount(),
      ]);
      if (!isCurrentUser()) return;
      items.value = nextItems;
      unreadCount.value = nextUnreadCount;
      loaded.value = true;
    } catch (caught) {
      if (isCurrentUser()) error.value = unknownErrorMessage(caught);
    } finally {
      if (isCurrentUser()) loading.value = false;
    }
  }

  async function markRead(notificationId: string) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");

    const item = items.value.find(
      (notification) => notification.id === notificationId,
    );
    const wasUnread = item?.read_at == null;
    const updated = await createRepository(backend.client).markNotificationRead(
      notificationId,
    );

    if (!updated) return false;
    if (item && wasUnread) {
      item.read_at = new Date().toISOString();
      unreadCount.value = Math.max(0, unreadCount.value - 1);
    }
    return true;
  }

  async function markAllRead() {
    const backend = getBackend();
    if (!backend) throw new Error("Backend unavailable");

    const updatedCount = await createRepository(
      backend.client,
    ).markAllNotificationsRead();
    if (updatedCount > 0) {
      const readAt = new Date().toISOString();
      for (const item of items.value) {
        if (!item.read_at) item.read_at = readAt;
      }
      unreadCount.value = 0;
    }
    return updatedCount;
  }

  async function dismiss(notificationId: string) {
    const backend = getBackend();
    if (!backend) throw new Error("无法连接服务");
    const ok = await createRepository(backend.client).dismissNotification(
      notificationId,
    );
    if (!ok) return false;
    const index = items.value.findIndex((item) => item.id === notificationId);
    if (index >= 0) {
      const [removed] = items.value.splice(index, 1);
      if (removed && !removed.read_at)
        unreadCount.value = Math.max(0, unreadCount.value - 1);
    }
    return true;
  }

  async function restore(notificationId: string) {
    const backend = getBackend();
    if (!backend) throw new Error("无法连接服务");
    const ok = await createRepository(backend.client).restoreNotification(
      notificationId,
    );
    if (ok) await load(true);
    return ok;
  }

  async function dismissRead() {
    const backend = getBackend();
    if (!backend) throw new Error("无法连接服务");
    const count = await createRepository(
      backend.client,
    ).dismissReadNotifications();
    if (count) items.value = items.value.filter((item) => !item.read_at);
    return count;
  }
  async function resolveTarget(
    notificationId: string,
  ): Promise<NotificationTarget | null> {
    const backend = getBackend();
    if (!backend) return null;
    return createRepository(backend.client).resolveNotificationTarget(
      notificationId,
    );
  }

  function reset() {
    loadGeneration += 1;
    items.value = [];
    unreadCount.value = 0;
    loading.value = false;
    error.value = null;
    loaded.value = false;
    loadedUserId.value = null;
  }

  return {
    items,
    unreadCount,
    loading,
    error,
    loaded,
    load,
    markRead,
    markAllRead,
    dismiss,
    restore,
    dismissRead,
    resolveTarget,
    reset,
  };
});
