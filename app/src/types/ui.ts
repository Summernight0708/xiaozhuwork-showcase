import type { Tables } from "@/types/database.generated";
import type { ProjectCapabilities, ProjectRole } from "@/domain/access-control";

export type ProjectRow = Tables<"projects">;
export type MembershipRow = Tables<"project_members">;
export type TaskRow = Tables<"tasks">;
export type TaskChangeProposalRow = Tables<"task_change_proposals">;
export type TaskDependencyRow = Tables<"task_dependencies">;
export type AssignmentOfferRow = Tables<"task_assignment_offers">;
export type TaskCollaboratorRow = Tables<"task_collaborators">;
export type TaskPrimaryHandoffRow = Tables<"task_primary_handoffs">;
export type FileRow = Tables<"task_files">;
export type FileVersionRow = Tables<"task_file_versions">;
export type FinalFileDesignationRow = Tables<"task_file_final_designations">;
export type FileUploadReservationRow = Tables<"file_upload_reservations">;
export type ReviewRoundRow = Tables<"task_review_rounds">;
export type ReviewRoundFileRow = Tables<"task_review_round_files">;
export type InvitationRow = Tables<"project_invitations">;
export type JoinRequestRow = Tables<"project_join_requests">;
export type NotificationRow = Tables<"notifications">;
export interface NotificationTarget {
  routeName:
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
}
export type ProfileRow = Tables<"profiles">;
export type ContributionConfirmationRow = Tables<"contribution_confirmations">;

export interface ProjectSummary {
  project: ProjectRow;
  membership: MembershipRow;
  role: ProjectRole;
  capabilities: ProjectCapabilities;
  myOpenTaskCount: number;
  taskCounts: {
    pending: number;
    inProgress: number;
    blocked: number;
    pendingReview: number;
    completed: number;
  };
}

export interface TaskFileVersion {
  fileVersionId: string;
  versionNumber: number;
  objectPath: string;
  originalName: string;
  mimeType: string;
  sizeBytes: number;
  sha256Hex: string;
  uploadedBy?: string;
  restoredFromVersionId?: string;
  createdAt: string;
  purpose?: "deliverable" | "reference";
}

export interface TaskFile {
  fileId: string;
  logicalName: string;
  purpose?: "deliverable" | "reference";
  currentVersionId?: string;
  version: number;
  createdBy?: string;
  createdAt: string;
  updatedAt: string;
  versions: TaskFileVersion[];
}

export interface TaskFilesResponse {
  taskId: string;
  files: TaskFile[];
}

export interface ContributionReportItem {
  taskId: string;
  memberUserId?: string;
  taskWeight?: number;
  share: number;
  contributionValue?: number;
  taskTitle: string;
  completedAt: string;
}

export interface ContributionReportSnapshot {
  projectId: string;
  reportId: string;
  state: "draft" | "formal";
  contributionMode: string;
  version: number;
  formalizedAt?: string;
  eligibleCount: number;
  confirmedCount: number;
  requiredCount: number;
  items: ContributionReportItem[];
}
