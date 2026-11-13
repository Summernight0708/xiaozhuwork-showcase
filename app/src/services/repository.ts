import type { SupabaseClient } from "@supabase/supabase-js";

import {
  capabilitiesForRole,
  normalizeProjectRole,
} from "@/domain/access-control";
import type {
  AccountEntitlement,
  ProjectEntitlement,
} from "@/domain/entitlements";
import type { Database, Json, Tables } from "@/types/database.generated";
import {
  checkedPrivacyRow,
  checkedPrivacyRows,
} from "@/domain/privacy-view-rows";
import type {
  ContributionReportSnapshot,
  ProjectSummary,
  TaskFile,
  TaskFilesResponse,
} from "@/types/ui";

type Client = SupabaseClient<Database>;
export interface ProjectStorageUsage {
  schemaVersion: 1;
  projectId: string;
  limitBytes: number;
  usedBytes: number;
  availableBytes: number;
  reservedBytes: number;
  overLimit: boolean;
}

function assertNoError(error: unknown): asserts error is null {
  if (error) throw new Error("Supabase request failed");
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function decodeAccountEntitlement(value: unknown): AccountEntitlement {
  const data = asRecord(value);
  const validPlan = data?.plan === "free" || data?.plan === "pro";
  const validState =
    data?.state === "free" ||
    data?.state === "scheduled" ||
    data?.state === "active" ||
    data?.state === "expired" ||
    data?.state === "cancelled";
  const validStartsAt =
    data?.startsAt === null || typeof data?.startsAt === "string";
  const validExpiresAt =
    data?.expiresAt === null || typeof data?.expiresAt === "string";
  const validVersion =
    typeof data?.version === "number" &&
    Number.isInteger(data.version) &&
    data.version >= 0;
  const validEffectivePair =
    (data?.state === "active" && data?.plan === "pro") ||
    (data?.state !== "active" && data?.plan === "free");

  if (
    !data ||
    data.ok !== true ||
    !validPlan ||
    !validState ||
    !validStartsAt ||
    !validExpiresAt ||
    !validVersion ||
    !validEffectivePair
  ) {
    throw new Error("Invalid account entitlement payload");
  }

  return {
    plan: data.plan as AccountEntitlement["plan"],
    state: data.state as AccountEntitlement["state"],
    startsAt: data.startsAt as string | null,
    expiresAt: data.expiresAt as string | null,
    version: data.version as number,
  };
}

function decodeProjectEntitlement(value: unknown): ProjectEntitlement {
  const data = asRecord(value);
  const validPlan = data?.plan === "free" || data?.plan === "pro";
  const validState =
    data?.state === "free" ||
    data?.state === "active" ||
    data?.state === "grace";
  const validSource =
    data?.source === "none" ||
    data?.source === "account_member" ||
    data?.source === "project_grant" ||
    data?.source === "grace";
  const validGraceExpiresAt =
    data?.graceExpiresAt === null || typeof data?.graceExpiresAt === "string";

  const validCombination =
    (data?.state === "free" &&
      data?.plan === "free" &&
      data?.source === "none" &&
      data?.graceExpiresAt === null) ||
    (data?.state === "active" &&
      data?.plan === "pro" &&
      (data?.source === "account_member" || data?.source === "project_grant") &&
      data?.graceExpiresAt === null) ||
    (data?.state === "grace" &&
      data?.plan === "pro" &&
      data?.source === "grace" &&
      typeof data?.graceExpiresAt === "string");

  if (
    !data ||
    data.ok !== true ||
    typeof data.projectId !== "string" ||
    !validPlan ||
    !validState ||
    !validSource ||
    !validGraceExpiresAt ||
    !validCombination
  ) {
    throw new Error("Invalid project entitlement payload");
  }

  return {
    projectId: data.projectId,
    plan: data.plan as ProjectEntitlement["plan"],
    state: data.state as ProjectEntitlement["state"],
    source: data.source as ProjectEntitlement["source"],
    graceExpiresAt: data.graceExpiresAt as string | null,
  };
}

function decodeTaskFiles(value: unknown): TaskFilesResponse {
  const envelope = asRecord(value);
  const data = asRecord(envelope?.data);
  if (
    envelope?.ok !== true ||
    !data ||
    typeof data.taskId !== "string" ||
    !Array.isArray(data.files)
  ) {
    throw new Error("Invalid task files payload");
  }

  const files: TaskFile[] = data.files.map((raw) => {
    const file = asRecord(raw);
    if (
      !file ||
      typeof file.fileId !== "string" ||
      typeof file.logicalName !== "string" ||
      !Array.isArray(file.versions)
    ) {
      throw new Error("Invalid task file");
    }
    return {
      fileId: file.fileId,
      logicalName: file.logicalName,
      purpose: file.purpose === "reference" ? "reference" : "deliverable",
      currentVersionId:
        typeof file.currentVersionId === "string"
          ? file.currentVersionId
          : undefined,
      version: typeof file.version === "number" ? file.version : 1,
      createdBy:
        typeof file.createdBy === "string" ? file.createdBy : undefined,
      createdAt: String(file.createdAt ?? ""),
      updatedAt: String(file.updatedAt ?? ""),
      versions: file.versions.map((rawVersion) => {
        const version = asRecord(rawVersion);
        if (
          !version ||
          typeof version.fileVersionId !== "string" ||
          typeof version.versionNumber !== "number"
        ) {
          throw new Error("Invalid task file version");
        }
        return {
          fileVersionId: version.fileVersionId,
          versionNumber: version.versionNumber,
          objectPath: String(version.objectPath ?? ""),
          originalName: String(version.originalName ?? ""),
          mimeType: String(version.mimeType ?? "application/octet-stream"),
          sizeBytes: Number(version.sizeBytes ?? 0),
          sha256Hex: String(version.sha256Hex ?? ""),
          uploadedBy:
            typeof version.uploadedBy === "string"
              ? version.uploadedBy
              : undefined,
          restoredFromVersionId:
            typeof version.restoredFromVersionId === "string"
              ? version.restoredFromVersionId
              : undefined,
          createdAt: String(version.createdAt ?? ""),
          purpose: file.purpose === "reference" ? "reference" : "deliverable",
        };
      }),
    };
  });

  return { taskId: data.taskId, files };
}

function decodeContributionReport(value: unknown): ContributionReportSnapshot {
  const data = asRecord(value);
  if (
    !data ||
    typeof data.projectId !== "string" ||
    typeof data.reportId !== "string" ||
    (data.state !== "draft" && data.state !== "formal") ||
    typeof data.version !== "number" ||
    !Array.isArray(data.items)
  ) {
    throw new Error("Invalid contribution report");
  }

  return {
    projectId: data.projectId,
    reportId: data.reportId,
    state: data.state,
    contributionMode: String(data.contributionMode ?? "facts_only"),
    version: data.version,
    formalizedAt:
      typeof data.formalizedAt === "string" ? data.formalizedAt : undefined,
    eligibleCount: Number(data.eligibleCount ?? 0),
    confirmedCount: Number(data.confirmedCount ?? 0),
    requiredCount: Number(data.requiredCount ?? 0),
    items: data.items.map((raw) => {
      const item = asRecord(raw);
      if (
        !item ||
        typeof item.taskId !== "string" ||
        typeof item.taskTitle !== "string"
      ) {
        throw new Error("Invalid contribution item");
      }
      return {
        taskId: item.taskId,
        memberUserId:
          typeof item.memberUserId === "string" ? item.memberUserId : undefined,
        taskWeight:
          typeof item.taskWeight === "number" ? item.taskWeight : undefined,
        share: Number(item.share ?? 1),
        contributionValue:
          typeof item.contributionValue === "number"
            ? item.contributionValue
            : undefined,
        taskTitle: item.taskTitle,
        completedAt: String(item.completedAt ?? ""),
      };
    }),
  };
}

export function createRepository(client: Client) {
  async function getProfile(userId: string) {
    const { data, error } = await client
      .from("profiles")
      .select("*")
      .eq("id", userId)
      .maybeSingle();
    assertNoError(error);
    return data;
  }

  async function updateProfile(userId: string, displayName: string) {
    const { data, error } = await client
      .from("profiles")
      .update({ display_name: displayName.trim() || null })
      .eq("id", userId)
      .select("*")
      .single();
    assertNoError(error);
    return data;
  }

  async function listProjectSummaries(
    userId: string,
  ): Promise<ProjectSummary[]> {
    const { data: rawMemberships, error: membershipError } = await client
      .from("project_members_visible")
      .select("*")
      .eq("user_id", userId)
      .eq("member_state", "active");
    assertNoError(membershipError);
    const memberships = checkedPrivacyRows("project_members", rawMemberships);
    if (!memberships.length) return [];

    const ids = memberships.map((membership) => membership.project_id);
    const [
      { data: projects, error: projectError },
      { data: tasks, error: taskError },
    ] = await Promise.all([
      client
        .from("projects")
        .select("*")
        .in("id", ids)
        .order("updated_at", { ascending: false }),
      client.from("tasks").select("*").in("project_id", ids),
    ]);
    assertNoError(projectError);
    assertNoError(taskError);

    return (projects ?? []).map((project) => {
      const membership = memberships.find(
        (item) => item.project_id === project.id,
      )!;
      const role = normalizeProjectRole({
        role: membership.role,
        isObserver: membership.is_observer,
      });
      const projectTasks = (tasks ?? []).filter(
        (task) => task.project_id === project.id,
      );
      const myOpenTaskCount = projectTasks.filter(
        (task) =>
          task.assignee_id === userId &&
          task.status !== "completed" &&
          task.status !== "canceled",
      ).length;
      return {
        project,
        membership,
        role,
        capabilities: capabilitiesForRole(
          role,
          project.allow_member_task_creation,
        ),
        myOpenTaskCount,
        taskCounts: {
          pending: projectTasks.filter(
            (task) => task.assignment_state !== "assigned",
          ).length,
          inProgress: projectTasks.filter(
            (task) => task.status === "in_progress",
          ).length,
          blocked: projectTasks.filter((task) => task.status === "blocked")
            .length,
          pendingReview: projectTasks.filter(
            (task) => task.status === "awaiting_review",
          ).length,
          completed: projectTasks.filter((task) => task.status === "completed")
            .length,
        },
      };
    });
  }

  async function getMyAccountEntitlement() {
    const { data, error } = await client.rpc("get_my_account_entitlement");
    assertNoError(error);
    return decodeAccountEntitlement(data);
  }

  async function getProjectEntitlement(projectId: string) {
    const { data, error } = await client.rpc("get_project_entitlement", {
      p_project_id: projectId,
    });
    assertNoError(error);
    return decodeProjectEntitlement(data);
  }

  async function getProject(projectId: string) {
    const { data, error } = await client
      .from("projects")
      .select("*")
      .eq("id", projectId)
      .maybeSingle();
    assertNoError(error);
    return data;
  }

  async function getMembership(projectId: string, userId: string) {
    const { data, error } = await client
      .from("project_members_visible")
      .select("*")
      .eq("project_id", projectId)
      .eq("user_id", userId)
      .eq("member_state", "active")
      .maybeSingle();
    assertNoError(error);
    return data ? checkedPrivacyRow("project_members", data) : null;
  }

  async function listMembers(projectId: string) {
    const { data, error } = await client
      .from("project_members_visible")
      .select("*")
      .eq("project_id", projectId)
      .eq("member_state", "active")
      .order("joined_at");
    assertNoError(error);
    return checkedPrivacyRows("project_members", data);
  }

  async function listTasks(projectId: string) {
    const { data, error } = await client
      .from("tasks")
      .select("*")
      .eq("project_id", projectId)
      .order("deadline_at");
    assertNoError(error);
    return data ?? [];
  }

  async function listTaskDependencies(projectId: string) {
    const { data, error } = await client
      .from("task_dependencies")
      .select("*")
      .eq("project_id", projectId)
      .order("created_at");
    assertNoError(error);
    return data ?? [];
  }

  async function listAssignmentOffers(projectId: string) {
    const { data, error } = await client
      .from("task_assignment_offers")
      .select("*")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false });
    assertNoError(error);
    return data ?? [];
  }

  async function listTaskCollaborators(projectId: string) {
    const { data, error } = await client
      .from("task_collaborators_visible")
      .select("*")
      .eq("project_id", projectId)
      .order("created_at");
    assertNoError(error);
    return checkedPrivacyRows("task_collaborators", data);
  }

  async function listTaskPrimaryHandoffs(projectId: string) {
    const { data, error } = await client
      .from("task_primary_handoffs_visible")
      .select("*")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false });
    assertNoError(error);
    return checkedPrivacyRows("task_primary_handoffs", data);
  }

  async function listTaskChangeProposals(projectId: string) {
    const { data, error } = await client
      .from("task_change_proposals_visible")
      .select("*")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false });
    assertNoError(error);
    return checkedPrivacyRows("task_change_proposals", data);
  }

  async function getTaskFiles(taskId: string) {
    const { data, error } = await client.rpc("get_task_files", {
      p_task_id: taskId,
    });
    assertNoError(error);
    return decodeTaskFiles(data);
  }

  async function listProjectFiles(projectId: string) {
    const [
      { data: files, error: fileError },
      { data: versions, error: versionError },
    ] = await Promise.all([
      client
        .from("task_files_visible")
        .select("*")
        .eq("project_id", projectId)
        .order("updated_at", { ascending: false }),
      client
        .from("task_file_versions_visible")
        .select("*")
        .eq("project_id", projectId)
        .order("created_at", { ascending: false }),
    ]);
    assertNoError(fileError);
    assertNoError(versionError);
    return {
      files: checkedPrivacyRows("task_files", files),
      versions: checkedPrivacyRows("task_file_versions", versions),
    };
  }

  async function listFinalFileDesignations(projectId: string) {
    const { data, error } = await client
      .from("task_file_final_designations")
      .select("*")
      .eq("project_id", projectId)
      .order("updated_at", { ascending: false });
    assertNoError(error);
    return data ?? [];
  }

  async function listFileReservations(projectId: string) {
    const { data, error } = await client
      .from("file_upload_reservations_visible")
      .select("*")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false });
    assertNoError(error);
    return checkedPrivacyRows("file_upload_reservations", data);
  }

  async function listReviews(projectId: string) {
    const { data, error } = await client
      .from("task_review_rounds")
      .select("*")
      .eq("project_id", projectId)
      .order("submitted_at", { ascending: false });
    assertNoError(error);
    return data ?? [];
  }

  async function listReviewFiles(projectId: string) {
    const { data, error } = await client
      .from("task_review_round_files")
      .select("*")
      .eq("project_id", projectId)
      .order("position");
    assertNoError(error);
    return data ?? [];
  }

  async function listInvitations(projectId: string) {
    const { data, error } = await client
      .from("project_invitations")
      .select("*")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false });
    assertNoError(error);
    return data ?? [];
  }

  async function listJoinRequests(projectId: string) {
    const { data, error } = await client
      .from("project_join_requests_visible")
      .select("*")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false });
    assertNoError(error);
    return checkedPrivacyRows("project_join_requests", data);
  }

  async function getContributionReport(projectId: string) {
    const { data, error } = await client.rpc(
      "get_project_contribution_report",
      { p_project_id: projectId },
    );
    assertNoError(error);
    const record = asRecord(data);
    if (record?.ok === false && record.code === "REPORT_NOT_READY") return null;
    return decodeContributionReport(data);
  }

  async function listContributionConfirmations(reportId: string) {
    const { data, error } = await client
      .from("contribution_confirmations")
      .select("*")
      .eq("report_id", reportId)
      .order("confirmed_at");
    assertNoError(error);
    return data ?? [];
  }

  async function listNotifications() {
    const { data, error } = await client
      .from("notifications")
      .select("*")
      .is("hidden_at", null)
      .order("created_at", { ascending: false });
    assertNoError(error);
    return data ?? [];
  }

  async function getUnreadNotificationCount() {
    const { data, error } = await client.rpc("get_unread_notification_count");
    assertNoError(error);
    return Number(data ?? 0);
  }

  async function markNotificationRead(id: string) {
    const { data, error } = await client.rpc("mark_notification_read", {
      p_notification_id: id,
    });
    assertNoError(error);
    return data === true;
  }

  async function markAllNotificationsRead() {
    const { data, error } = await client.rpc("mark_all_notifications_read");
    assertNoError(error);
    return Number(data ?? 0);
  }

  async function dismissNotification(id: string) {
    const { data, error } = await client.rpc("dismiss_notification", {
      p_notification_id: id,
    });
    assertNoError(error);
    return data === true;
  }

  async function restoreNotification(id: string) {
    const { data, error } = await client.rpc("restore_notification", {
      p_notification_id: id,
    });
    assertNoError(error);
    return data === true;
  }

  async function dismissReadNotifications() {
    const { data, error } = await client.rpc("dismiss_read_notifications");
    assertNoError(error);
    return Number(data ?? 0);
  }
  async function resolveNotificationTarget(id: string) {
    const { data, error } = await client.rpc("resolve_notification_target", {
      p_notification_id: id,
    });
    assertNoError(error);
    if (data === null) return null;
    const target = asRecord(data);
    if (!target || typeof target.routeName !== "string") {
      throw new Error("Invalid notification target");
    }

    const globalRoutes = [
      "help-center",
      "download",
      "upgrade",
      "notifications",
    ] as const;
    const projectRoutes = [
      "task-detail",
      "review-detail",
      "project-invitations",
      "project-members",
      "project-overview",
    ] as const;

    if (
      globalRoutes.includes(target.routeName as (typeof globalRoutes)[number])
    ) {
      return {
        routeName: target.routeName as (typeof globalRoutes)[number],
      };
    }

    if (
      !projectRoutes.includes(
        target.routeName as (typeof projectRoutes)[number],
      ) ||
      typeof target.projectId !== "string"
    ) {
      throw new Error("Invalid notification target");
    }
    if (target.entityId !== undefined && typeof target.entityId !== "string") {
      throw new Error("Invalid notification target entity");
    }
    return {
      routeName: target.routeName as (typeof projectRoutes)[number],
      projectId: target.projectId,
      entityId:
        typeof target.entityId === "string" ? target.entityId : undefined,
    };
  }
  async function getProjectStorageUsage(
    projectId: string,
  ): Promise<ProjectStorageUsage> {
    const { data, error } = await client.rpc("get_project_storage_usage", {
      p_project_id: projectId,
    });
    assertNoError(error);
    const envelope = asRecord(data);
    const usage = asRecord(envelope?.data);
    if (
      envelope?.ok !== true ||
      usage?.schemaVersion !== 1 ||
      usage.projectId !== projectId ||
      !["limitBytes", "usedBytes", "availableBytes", "reservedBytes"].every(
        (key) =>
          typeof usage[key] === "number" &&
          Number.isSafeInteger(usage[key]) &&
          (usage[key] as number) >= 0,
      ) ||
      typeof usage.overLimit !== "boolean"
    ) {
      throw new Error("Invalid project storage usage response");
    }
    return usage as unknown as ProjectStorageUsage;
  }

  async function createSignedFileUrl(objectPath: string) {
    const { data, error } = await client.storage
      .from("teamup-files")
      .createSignedUrl(objectPath, 600);
    assertNoError(error);
    return data.signedUrl;
  }

  async function createFileVersionSignedAccess(
    fileVersionId: string,
    projectId: string,
    expiresInSeconds: number,
  ) {
    const { data: version, error: versionError } = await client
      .from("task_file_versions_visible")
      .select("*")
      .eq("id", fileVersionId)
      .eq("project_id", projectId)
      .maybeSingle();
    assertNoError(versionError);
    if (!version) throw new Error("File version unavailable");
    const decodedVersion = checkedPrivacyRow("task_file_versions", version);

    const { data, error } = await client.storage
      .from("teamup-files")
      .createSignedUrl(decodedVersion.object_path, expiresInSeconds);
    assertNoError(error);
    return { version: decodedVersion, signedUrl: data.signedUrl };
  }

  async function exportContributionReport(
    reportId: string,
    format: "csv" | "pdf",
  ) {
    const { data, error } = await client.functions.invoke(
      "export-project-report",
      {
        body: { reportId, format },
      },
    );
    assertNoError(error);
    if (data instanceof Blob) return data;
    if (typeof data === "string") {
      return new Blob([data], {
        type: format === "csv" ? "text/csv;charset=utf-8" : "application/pdf",
      });
    }
    if (data instanceof ArrayBuffer) {
      return new Blob([data], {
        type: format === "csv" ? "text/csv;charset=utf-8" : "application/pdf",
      });
    }
    throw new Error("Invalid report export response");
  }

  return {
    getProfile,
    updateProfile,
    listProjectSummaries,
    getMyAccountEntitlement,
    getProjectEntitlement,
    getProject,
    getMembership,
    listMembers,
    listTasks,
    listTaskDependencies,
    listAssignmentOffers,
    listTaskCollaborators,
    listTaskPrimaryHandoffs,
    listTaskChangeProposals,
    getTaskFiles,
    listProjectFiles,
    listFinalFileDesignations,
    listFileReservations,
    listReviews,
    listReviewFiles,
    listInvitations,
    listJoinRequests,
    getContributionReport,
    listContributionConfirmations,
    listNotifications,
    getUnreadNotificationCount,
    markNotificationRead,
    markAllNotificationsRead,
    dismissNotification,
    restoreNotification,
    dismissReadNotifications,
    resolveNotificationTarget,
    getProjectStorageUsage,
    createSignedFileUrl,
    createFileVersionSignedAccess,
    exportContributionReport,
  };
}

export type XiaozhuWorkRepository = ReturnType<typeof createRepository>;
export type ProjectRow = Tables<"projects">;
export type JsonValue = Json;
