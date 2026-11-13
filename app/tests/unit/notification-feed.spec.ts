import { describe, expect, it } from "vitest";

import {
  notificationBelongsInFeed,
  notificationDestination,
} from "@/domain/notification-feed";
import type { NotificationRow, NotificationTarget } from "@/types/ui";

function notification(type: string): NotificationRow {
  return {
    id: "notification-1",
    project_id: "project-1",
    recipient_id: "user-1",
    notification_type: type,
    title: "通知",
    message: "上下文",
    entity_type: "task",
    entity_id: "task-1",
    read_at: null,
    hidden_at: null,
    created_at: "2026-10-04T00:00:00Z",
    source_event_id: 1,
  };
}

const taskTarget: NotificationTarget = {
  routeName: "task-detail",
  projectId: "project-1",
  entityId: "task-1",
};

describe("notification feed policy", () => {
  it("excludes light binding, ordinary preview and upload progress but keeps strong binding", () => {
    expect(
      notificationBelongsInFeed(notification("light_binding_upstream_updated")),
    ).toBe(false);
    expect(notificationBelongsInFeed(notification("file_preview_opened"))).toBe(
      false,
    );
    expect(
      notificationBelongsInFeed(notification("file_upload_progress")),
    ).toBe(false);
    expect(
      notificationBelongsInFeed(
        notification("strong_binding_upstream_updated"),
      ),
    ).toBe(true);
  });

  it("routes strong binding updates to the upstream artifact section", () => {
    expect(
      notificationDestination(
        notification("strong_binding_upstream_updated"),
        taskTarget,
      ),
    ).toMatchObject({
      kind: "task-detail-section",
      routeName: "task-detail",
      query: { section: "upstream-artifacts" },
    });
  });

  it("routes help/rework and task-change facts to their task-detail sections", () => {
    expect(
      notificationDestination(notification("task_help_requested"), taskTarget),
    ).toMatchObject({ query: { section: "collaboration-issues" } });
    expect(
      notificationDestination(
        notification("upstream_rework_requested"),
        taskTarget,
      ),
    ).toMatchObject({ query: { section: "collaboration-issues" } });
    expect(
      notificationDestination(
        notification("task_change_confirmation"),
        taskTarget,
      ),
    ).toMatchObject({ query: { section: "changes" } });
  });

  it("routes system announcements to allow-listed global pages without a project id", () => {
    expect(
      notificationDestination(notification("system_announcement"), {
        routeName: "help-center",
      }),
    ).toEqual({
      kind: "global",
      routeName: "help-center",
    });
  });
  it("routes assignment/collaborator response work to My Work after authorization", () => {
    expect(
      notificationDestination(notification("task_assignment"), taskTarget),
    ).toMatchObject({
      kind: "workspace-action",
      routeName: "project-todos",
      query: { focus: "response" },
    });
    expect(
      notificationDestination(
        notification("collaborator_invitation"),
        taskTarget,
      ),
    ).toMatchObject({ routeName: "project-todos" });
  });
});
