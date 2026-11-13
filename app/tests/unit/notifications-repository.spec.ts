import { describe, expect, it, vi } from "vitest";

import { createRepository } from "@/services/repository";

function createClient() {
  const order = vi.fn().mockResolvedValue({
    data: [
      {
        id: "notification-1",
        project_id: "project-1",
        recipient_id: "user-1",
        notification_type: "task_assignment",
        title: "新任务指派",
        entity_type: "task",
        entity_id: "task-1",
        message: "你收到了一项待确认的任务指派。",
        read_at: null,
        created_at: "2026-09-30T10:00:00Z",
        source_event_id: 1,
      },
    ],
    error: null,
  });
  const is = vi.fn(() => ({ order }));
  const select = vi.fn(() => ({ is }));
  const from = vi.fn(() => ({ select }));
  const rpc = vi.fn(async (name: string) => {
    if (name === "get_unread_notification_count")
      return { data: 1, error: null };
    if (name === "mark_notification_read") return { data: true, error: null };
    if (name === "mark_all_notifications_read") return { data: 1, error: null };
    if (name === "dismiss_notification") return { data: true, error: null };
    if (name === "restore_notification") return { data: true, error: null };
    if (name === "dismiss_read_notifications") return { data: 1, error: null };
    if (name === "resolve_notification_target") {
      return {
        data: {
          routeName: "task-detail",
          projectId: "project-1",
          entityId: "task-1",
        },
        error: null,
      };
    }
    throw new Error(`Unexpected RPC: ${name}`);
  });

  return {
    client: { from, rpc, storage: {}, functions: {} } as never,
    from,
    select,
    is,
    order,
    rpc,
  };
}

describe("notification repository", () => {
  it("relies on recipient RLS for listing and does not send a caller-selected recipient id", async () => {
    const { client, from, select, is, order } = createClient();
    const repository = createRepository(client);

    const rows = await repository.listNotifications();

    expect(rows).toHaveLength(1);
    expect(from).toHaveBeenCalledWith("notifications");
    expect(select).toHaveBeenCalledWith("*");
    expect(is).toHaveBeenCalledWith("hidden_at", null);
    expect(order).toHaveBeenCalledWith("created_at", { ascending: false });
  });

  it("uses controlled RPCs for unread and read-state mutations", async () => {
    const { client, rpc } = createClient();
    const repository = createRepository(client);

    await expect(repository.getUnreadNotificationCount()).resolves.toBe(1);
    await expect(
      repository.markNotificationRead("notification-1"),
    ).resolves.toBe(true);
    await expect(repository.markAllNotificationsRead()).resolves.toBe(1);

    expect(rpc).toHaveBeenCalledWith("mark_notification_read", {
      p_notification_id: "notification-1",
    });
    expect(rpc).toHaveBeenCalledWith("mark_all_notifications_read");
  });

  it("hides and restores notifications only through recipient-scoped RPCs", async () => {
    const { client, rpc } = createClient();
    const repository = createRepository(client);
    await expect(
      repository.dismissNotification("notification-1"),
    ).resolves.toBe(true);
    await expect(
      repository.restoreNotification("notification-1"),
    ).resolves.toBe(true);
    await expect(repository.dismissReadNotifications()).resolves.toBe(1);
    expect(rpc).toHaveBeenCalledWith("dismiss_notification", {
      p_notification_id: "notification-1",
    });
    expect(rpc).toHaveBeenCalledWith("restore_notification", {
      p_notification_id: "notification-1",
    });
    expect(rpc).toHaveBeenCalledWith("dismiss_read_notifications");
  });
  it("accepts only allow-listed project-independent system destinations", async () => {
    const { client, rpc } = createClient();
    rpc.mockResolvedValueOnce({
      data: { routeName: "help-center" },
      error: null,
    } as never);
    const repository = createRepository(client);

    await expect(
      repository.resolveNotificationTarget("notification-system"),
    ).resolves.toEqual({ routeName: "help-center" });
  });
  it("decodes only an allow-listed server-resolved route target", async () => {
    const { client } = createClient();
    const repository = createRepository(client);

    await expect(
      repository.resolveNotificationTarget("notification-1"),
    ).resolves.toEqual({
      routeName: "task-detail",
      projectId: "project-1",
      entityId: "task-1",
    });
  });
});
