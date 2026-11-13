import type { NotificationRow, NotificationTarget } from "@/types/ui";

export type NotificationDestinationKind =
  | "workspace-action"
  | "review-round"
  | "task-detail"
  | "task-detail-section"
  | "project"
  | "global";

export interface NotificationDestination {
  kind: NotificationDestinationKind;
  routeName:
    | "project-todos"
    | "task-detail"
    | "review-detail"
    | "project-invitations"
    | "project-members"
    | "project-overview"
    | "help-center"
    | "download"
    | "upgrade"
    | "notifications";
  projectId?: string;
  entityId?: string;
  query?: Record<string, string>;
}

const EXCLUDED_EVENT_MARKERS = [
  "light_binding",
  "file_preview",
  "preview_opened",
  "download_started",
  "file_upload_progress",
];

const GLOBAL_NOTIFICATION_ROUTES = new Set([
  "help-center",
  "download",
  "upgrade",
  "notifications",
]);

export function notificationBelongsInFeed(item: NotificationRow): boolean {
  const type = item.notification_type.toLowerCase();
  return !EXCLUDED_EVENT_MARKERS.some((marker) => type.includes(marker));
}

export function notificationDestination(
  item: NotificationRow,
  target: NotificationTarget,
): NotificationDestination {
  const type = item.notification_type.toLowerCase();

  if (GLOBAL_NOTIFICATION_ROUTES.has(target.routeName)) {
    return {
      kind: "global",
      routeName: target.routeName as
        "help-center" | "download" | "upgrade" | "notifications",
    };
  }

  if (!target.projectId) {
    return { kind: "global", routeName: "notifications" };
  }

  if (
    type.includes("collaborator") ||
    type === "task_assignment" ||
    type.includes("assignment_accept")
  ) {
    return {
      kind: "workspace-action",
      routeName: "project-todos",
      projectId: target.projectId,
      query: { focus: "response" },
    };
  }

  if (target.routeName === "review-detail") {
    return {
      kind: "review-round",
      routeName: "review-detail",
      projectId: target.projectId,
      entityId: target.entityId,
    };
  }

  if (target.routeName === "task-detail") {
    if (type.includes("strong_binding") || type.includes("artifact_binding")) {
      return {
        kind: "task-detail-section",
        routeName: "task-detail",
        projectId: target.projectId,
        entityId: target.entityId,
        query: { section: "upstream-artifacts" },
      };
    }
    if (type.includes("help") || type.includes("rework")) {
      return {
        kind: "task-detail-section",
        routeName: "task-detail",
        projectId: target.projectId,
        entityId: target.entityId,
        query: { section: "collaboration-issues" },
      };
    }
    if (type.includes("task_change")) {
      return {
        kind: "task-detail-section",
        routeName: "task-detail",
        projectId: target.projectId,
        entityId: target.entityId,
        query: { section: "changes" },
      };
    }
    return {
      kind: "task-detail",
      routeName: "task-detail",
      projectId: target.projectId,
      entityId: target.entityId,
    };
  }

  return {
    kind: "project",
    routeName: target.routeName as
      "project-invitations" | "project-members" | "project-overview",
    projectId: target.projectId,
    entityId: target.entityId,
  };
}
