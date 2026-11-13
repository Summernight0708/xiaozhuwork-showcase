import type { User } from "@supabase/supabase-js";
import { createPinia, setActivePinia } from "pinia";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  listNotifications: vi.fn(),
  getUnreadNotificationCount: vi.fn(),
  markNotificationRead: vi.fn(),
  markAllNotificationsRead: vi.fn(),
  dismissNotification: vi.fn(),
  restoreNotification: vi.fn(),
  dismissReadNotifications: vi.fn(),
  resolveNotificationTarget: vi.fn(),
}));

vi.mock("@/services/backend", () => ({
  getBackend: () => ({ client: {} }),
}));

vi.mock("@/services/repository", () => ({
  createRepository: () => mocks,
}));

import { useAuthStore } from "@/stores/auth";
import { useNotificationsStore } from "@/stores/notifications";

function authUser(id: string) {
  return { id } as unknown as User;
}

const unread = {
  id: "notification-1",
  project_id: "project-1",
  recipient_id: "user-a",
  notification_type: "task_assignment",
  title: "新任务指派",
  message: "你收到了一项待确认的任务指派。",
  entity_type: "task",
  entity_id: "task-1",
  read_at: null,
  created_at: "2026-09-30T10:00:00Z",
  source_event_id: "event-1",
};

describe("notifications store", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    mocks.listNotifications.mockImplementation(async () => [
      { ...unread, read_at: null },
    ]);
    mocks.getUnreadNotificationCount.mockResolvedValue(1);
    mocks.markNotificationRead.mockResolvedValue(true);
    mocks.markAllNotificationsRead.mockResolvedValue(1);
    mocks.dismissNotification.mockResolvedValue(true);
    mocks.restoreNotification.mockResolvedValue(true);
    mocks.dismissReadNotifications.mockResolvedValue(1);
    mocks.resolveNotificationTarget.mockResolvedValue({
      routeName: "task-detail",
      projectId: "project-1",
      entityId: "task-1",
    });
  });

  it("loads a real list and authoritative unread count for the authenticated account", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-a") });
    const store = useNotificationsStore();

    await store.load();

    expect(store.items).toHaveLength(1);
    expect(store.unreadCount).toBe(1);
    expect(mocks.listNotifications).toHaveBeenCalledOnce();
    expect(mocks.getUnreadNotificationCount).toHaveBeenCalledOnce();
  });

  it("marks one notification read and keeps the badge count in sync", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-a") });
    const store = useNotificationsStore();
    await store.load();

    await store.markRead("notification-1");

    expect(mocks.markNotificationRead).toHaveBeenCalledWith("notification-1");
    expect(store.items[0]?.read_at).not.toBeNull();
    expect(store.unreadCount).toBe(0);
  });

  it("marks all visible notifications read", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-a") });
    const store = useNotificationsStore();
    await store.load();

    await store.markAllRead();

    expect(mocks.markAllNotificationsRead).toHaveBeenCalledOnce();
    expect(store.unreadCount).toBe(0);
    expect(store.items.every((item) => item.read_at !== null)).toBe(true);
  });

  it("fails closed when a notification target can no longer be resolved", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-a") });
    const store = useNotificationsStore();
    mocks.resolveNotificationTarget.mockResolvedValueOnce(null);

    await expect(store.resolveTarget("notification-1")).resolves.toBeNull();
  });

  it("clears account-scoped state when reset", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-a") });
    const store = useNotificationsStore();
    await store.load();

    store.reset();

    expect(store.items).toEqual([]);
    expect(store.unreadCount).toBe(0);
    expect(store.loaded).toBe(false);
  });
  it("hides and restores a notice without discarding its authoritative read state", async () => {
    useAuthStore().$patch({ user: authUser("user-a") });
    const store = useNotificationsStore();
    await store.load();
    await expect(store.dismiss("notification-1")).resolves.toBe(true);
    expect(store.items).toHaveLength(0);
    expect(store.unreadCount).toBe(0);
    await expect(store.restore("notification-1")).resolves.toBe(true);
    expect(store.items).toHaveLength(1);
    expect(store.unreadCount).toBe(1);
    await store.markRead("notification-1");
    await expect(store.dismissRead()).resolves.toBe(1);
    expect(store.items).toHaveLength(0);
  });
});
