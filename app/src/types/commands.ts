import type { SubmissionFileType } from "@/domain/submission-file-types";

export type DomainErrorCode =
  | "UNAUTHENTICATED"
  | "NOT_FOUND_OR_NOT_AUTHORIZED"
  | "VALIDATION_FAILED"
  | "IDEMPOTENCY_KEY_REUSED"
  | "INVITE_UNAVAILABLE"
  | "INVITE_EXHAUSTED"
  | "ALREADY_MEMBER"
  | "JOIN_REQUEST_PENDING"
  | "TASK_ALREADY_CLAIMED"
  | "ASSIGNMENT_NOT_PENDING"
  | "STALE_VERSION"
  | "NOT_AUTHORIZED"
  | "INVALID_TRANSITION"
  | "QUOTA_EXCEEDED"
  | "ACTIVE_FREE_PROJECT_LIMIT_REACHED"
  | "PROJECT_MEMBER_LIMIT_REACHED"
  | "CONCURRENT_TASK_LIMIT_REACHED"
  | "DDL_NOT_IN_FUTURE"
  | "CONFIRMATION_REQUIRED"
  | "FEATURE_DISABLED"
  | "UNSAFE_FILE_TYPE"
  | "SHARE_EXPIRED"
  | "FILE_TYPE_NOT_ALLOWED"
  | "STORAGE_QUOTA_EXCEEDED"
  | "FILE_VALIDATION_FAILED"
  | "UPLOAD_NOT_READY"
  | "PROJECT_NOT_ACTIVE"
  | "REVIEW_NOT_PENDING"
  | "REPORT_NOT_READY";

export type CommandFailureDetail = string | number | boolean;

export interface CommandSuccess<T> {
  ok: true;
  data: T;
  requestId: string;
  replayed: boolean;
  aggregateType: string;
  aggregateId: string;
  aggregateVersion: number;
}

export interface CommandFailure {
  ok: false;
  code: DomainErrorCode;
  requestId: string;
  replayed: boolean;
  field?: string;
  currentVersion?: number;
  details?: Record<string, CommandFailureDetail>;
}

export type CommandResult<T> = CommandSuccess<T> | CommandFailure;

export interface CreateProjectInput {
  requestId: string;
  expectedVersion: 0;
  name: string;
  courseName?: string;
  description?: string;
  startAt?: string;
  deadlineAt: string;
  timezone?: string;
  contributionMode?: string;
  allowMemberTaskCreation?: boolean;
  requireRealName?: boolean;
  requireStudentNumber?: boolean;
}

export interface CreateProjectData {
  projectId: string;
  leaderMembershipId: string;
}

export interface CreateProjectInviteInput {
  projectId: string;
  requestId: string;
  expectedVersion: number;
  mode: "direct" | "approval";
  expiresInDays?: number;
  maxUses?: number;
}

export interface CreateProjectInviteData {
  invitationId: string;
  token: string;
  expiresAt: string;
  invitationVersion: number;
}

export interface RenewProjectInviteInput {
  projectId: string;
  invitationId: string;
  requestId: string;
  expectedVersion: number;
  extendDays?: number;
}

export interface RenewProjectInviteData {
  invitationId: string;
  expiresAt: string;
  invitationVersion: number;
}

export interface RevokeProjectInviteInput {
  projectId: string;
  invitationId: string;
  requestId: string;
  expectedVersion: number;
}

export interface RevokeProjectInviteData {
  invitationId: string;
  revokedAt: string;
  canceledJoinRequestCount: number;
}

export interface JoinProjectViaInviteInput {
  token: string;
  requestId: string;
  expectedVersion: number;
}

export interface JoinProjectViaInviteData {
  projectId: string;
  outcome: "joined" | "pending_approval";
  membershipId?: string;
  joinRequestId?: string;
  invitationVersion: number;
}

export interface ReviewProjectJoinRequestInput {
  projectId: string;
  joinRequestId: string;
  action: "approve" | "reject";
  requestId: string;
  expectedVersion: number;
}

export interface ReviewProjectJoinRequestData {
  projectId: string;
  joinRequestId: string;
  state: "approved" | "rejected";
  membershipId?: string;
}

export interface CreateTaskInput {
  projectId: string;
  requestId: string;
  expectedVersion: number;
  title: string;
  description?: string;
  deadlineAt: string;
  weight?: number;
  assignmentMode: "claimable" | "direct";
  assigneeId?: string;
  requiredSubmissionFileType?: SubmissionFileType | null;
  requiredSubmissionFileTypes?: SubmissionFileType[];
  requiresReview?: boolean;
}

export interface CreateTaskData {
  taskId: string;
  taskVersion: number;
  assignmentOfferId?: string;
  assignmentOfferVersion?: number;
}

export interface ClaimTaskInput {
  projectId: string;
  taskId: string;
  requestId: string;
  expectedVersion: number;
}

export interface ClaimTaskData {
  taskId: string;
  assigneeId: string;
  acceptedAt: string;
}

export interface RespondToTaskAssignmentInput {
  projectId: string;
  taskId: string;
  assignmentOfferId: string;
  requestId: string;
  expectedVersion: number;
  action: "accept" | "reject";
}

export interface RespondToTaskAssignmentData {
  taskId: string;
  assignmentOfferId: string;
  outcome: "accepted" | "rejected";
  taskVersion: number;
}

export type TaskCollaboratorState =
  "pending" | "accepted" | "rejected" | "removed";

export interface TaskCollaboratorCommandData {
  taskId: string;
  collaboratorId: string;
  userId: string;
  state: TaskCollaboratorState;
  collaboratorVersion: number;
}

export interface InviteTaskCollaboratorInput {
  projectId: string;
  taskId: string;
  userId: string;
  requestId: string;
  expectedVersion: number;
}

export interface RespondToTaskCollaboratorInput {
  projectId: string;
  taskId: string;
  collaboratorId: string;
  action: "accept" | "reject";
  requestId: string;
  expectedVersion: number;
}

export interface RemoveTaskCollaboratorInput {
  projectId: string;
  taskId: string;
  collaboratorId: string;
  requestId: string;
  expectedVersion: number;
}

export interface LeaveTaskCollaborationInput {
  projectId: string;
  taskId: string;
  collaboratorId: string;
  requestId: string;
  expectedVersion: number;
}

export interface UpdateTaskProgressInput {
  projectId: string;
  taskId: string;
  requestId: string;
  expectedVersion: number;
  status: "in_progress" | "blocked";
  progressText: string;
  blockedReason?: string;
}

export interface UpdateTaskProgressData {
  taskId: string;
  status: "in_progress" | "blocked";
  progressText: string;
  blockedReason?: string;
  updatedAt: string;
}

export interface ReserveTaskFileUploadInput {
  projectId: string;
  taskId: string;
  requestId: string;
  expectedVersion: number;
  mode: "new_file" | "new_version";
  targetFileId?: string;
  originalName: string;
  declaredMimeType: string;
  declaredSizeBytes: number;
}

export interface ReserveTaskFileUploadData {
  reservationId: string;
  objectPath: string;
  expiresAt: string;
}

export interface MarkTaskFileReferenceInput {
  projectId: string;
  taskId: string;
  fileId: string;
  requestId: string;
  expectedVersion: number;
}

export interface MarkTaskFileReferenceData {
  taskId: string;
  fileId: string;
  purpose: "reference";
  fileVersion: number;
  changed: boolean;
}

export interface SubmitTaskForReviewInput {
  projectId: string;
  taskId: string;
  submissionText?: string;
  fileVersionIds: string[];
  requestId: string;
  expectedVersion: number;
}

export interface SubmitTaskForReviewData {
  taskId: string;
  reviewRoundId: string;
  roundNumber: number;
  submittedAt: string;
}

export interface ReviewTaskSubmissionInput {
  projectId: string;
  taskId: string;
  reviewRoundId: string;
  action: "approve" | "reject" | "request_changes";
  rejectionReason?: string;
  requestId: string;
  expectedVersion: number;
}

export interface ReviewTaskSubmissionData {
  taskId: string;
  reviewRoundId: string;
  outcome: "approve" | "reject" | "request_changes";
  taskStatus: "completed" | "in_progress";
  reviewedAt: string;
  rejectionReason?: string;
}

export interface CorrectTaskReviewRequestChangesInput {
  projectId: string;
  taskId: string;
  reviewRoundId: string;
  requestId: string;
  expectedTaskVersion: number;
  expectedReviewVersion: number;
}

export interface CorrectTaskReviewRequestChangesData {
  taskId: string;
  sourceReviewRoundId: string;
  reviewRoundId: string;
  roundNumber: number;
  taskVersion: number;
  reviewRoundVersion: number;
}

export type TaskPrimaryHandoffState =
  "pending" | "accepted" | "rejected" | "canceled";

export interface TaskPrimaryHandoffCommandData {
  taskId: string;
  handoffId: string;
  fromUserId: string;
  toUserId: string;
  state: TaskPrimaryHandoffState;
  handoffVersion: number;
  taskVersion: number;
}

export interface RequestTaskPrimaryHandoffInput {
  projectId: string;
  taskId: string;
  targetUserId: string;
  requestId: string;
  expectedTaskVersion: number;
}

export interface RespondTaskPrimaryHandoffInput {
  projectId: string;
  taskId: string;
  handoffId: string;
  action: "accept" | "reject";
  requestId: string;
  expectedHandoffVersion: number;
  expectedTaskVersion: number;
}

export interface CancelTaskPrimaryHandoffInput {
  projectId: string;
  taskId: string;
  handoffId: string;
  requestId: string;
  expectedHandoffVersion: number;
  expectedTaskVersion: number;
}

export interface UnassignTaskPrimaryInput {
  projectId: string;
  taskId: string;
  requestId: string;
  expectedTaskVersion: number;
}

export interface UnassignTaskPrimaryData {
  taskId: string;
  taskVersion: number;
  assignmentState: "claimable";
}

export interface CreateContributionReportInput {
  projectId: string;
  requestId: string;
  expectedVersion: number;
}

export interface CreateContributionReportData {
  projectId: string;
  reportId: string;
  reportVersion: number;
  itemCount: number;
  state: "draft";
}

export interface ConfirmContributionReportInput {
  projectId: string;
  reportId: string;
  requestId: string;
  expectedVersion: number;
}

export interface ConfirmContributionReportData {
  projectId: string;
  reportId: string;
  state: "draft" | "formal";
  confirmedCount: number;
  eligibleCount: number;
  requiredCount: number;
  formalized: boolean;
}

export type ProjectMemberRole = "leader" | "admin" | "member" | "observer";

export interface UpdateProjectMemberRoleInput {
  projectId: string;
  membershipId: string;
  targetRole: Exclude<ProjectMemberRole, "leader">;
  requestId: string;
  expectedVersion: number;
}

export interface UpdateProjectMemberRoleData {
  membershipId: string;
  role: Exclude<ProjectMemberRole, "leader">;
  membershipVersion: number;
  projectVersion: number;
  changed: boolean;
}

export interface RemoveProjectMemberInput {
  projectId: string;
  membershipId: string;
  requestId: string;
  expectedVersion: number;
}

export interface RemoveProjectMemberData {
  membershipId: string;
  state: "removed";
  membershipVersion: number;
  projectVersion: number;
  releasedTaskCount: number;
}

export interface LeaveProjectInput {
  projectId: string;
  requestId: string;
  expectedVersion: number;
}

export interface LeaveProjectData {
  membershipId: string;
  state: "left";
  membershipVersion: number;
  projectVersion: number;
  releasedTaskCount: number;
}

export interface TransferProjectLeadershipInput {
  projectId: string;
  targetMembershipId: string;
  requestId: string;
  expectedVersion: number;
}

export interface TransferProjectLeadershipData {
  projectId: string;
  leaderUserId: string;
  leaderMembershipId: string;
  projectVersion: number;
}

export interface EditTaskInput {
  projectId: string;
  taskId: string;
  requestId: string;
  expectedVersion: number;
  title: string;
  description?: string;
  deadlineAt: string;
  weight?: number;
  requiredSubmissionFileType?: SubmissionFileType | null;
  requiredSubmissionFileTypes?: SubmissionFileType[];
}

export interface EditTaskData {
  taskId: string;
  taskVersion: number;
  changed: boolean;
  title: string;
  description?: string;
  deadlineAt: string;
  weight?: number;
  requiredSubmissionFileType?: SubmissionFileType;
  requiredSubmissionFileTypes?: SubmissionFileType[];
}

export interface ProposeTaskChangeInput {
  projectId: string;
  taskId: string;
  deadlineAt: string;
  weight?: number;
  requiredSubmissionFileType?: SubmissionFileType | null;
  requiredSubmissionFileTypes?: SubmissionFileType[];
  requestId: string;
  expectedTaskVersion: number;
}

export interface ProposeTaskChangeData {
  proposalId: string;
  taskId: string;
  state: "pending";
  proposalVersion: number;
  createdAt: string;
}

export interface RespondToTaskChangeInput {
  projectId: string;
  taskId: string;
  proposalId: string;
  action: "approve" | "reject";
  rejectionReason?: string;
  requestId: string;
  expectedProposalVersion: number;
}

export interface RespondToTaskChangeData {
  proposalId: string;
  taskId: string;
  state: "approved" | "rejected";
  proposalVersion: number;
  taskVersion: number;
  decidedAt: string;
  decisionReason?: string;
}

export interface SetTaskDependenciesInput {
  projectId: string;
  downstreamTaskId: string;
  upstreamTaskIds: string[];
  requestId: string;
  expectedVersion: number;
}

export interface SetTaskDependenciesData {
  taskId: string;
  taskVersion: number;
  changed: boolean;
  upstreamTaskIds: string[];
}

export interface SetTaskFileVersionFinalInput {
  projectId: string;
  fileVersionId: string;
  requestId: string;
  expectedVersion: number;
  isFinal: boolean;
}

export interface SetTaskFileVersionFinalData {
  fileVersionId: string;
  fileId: string;
  taskId: string;
  isFinal: boolean;
  designationVersion: number;
  changed: boolean;
}

export interface UpdateProjectSettingsInput {
  projectId: string;
  requestId: string;
  expectedVersion: number;
  name: string;
  courseName?: string;
  description?: string;
  startAt?: string;
  deadlineAt: string;
  timezone: string;
  contributionMode: "weighted" | "facts_only";
  allowMemberTaskCreation?: boolean;
  autoPenaltyEnabled: boolean;
  requireRealName: boolean;
  requireStudentNumber: boolean;
}

export interface UpdateProjectSettingsData {
  projectId: string;
  projectVersion: number;
  changed: boolean;
}

export interface PreviewProjectInviteInput {
  token: string;
}

export interface PreviewProjectInviteData {
  projectId: string;
  projectName: string;
  projectDeadlineAt: string;
  requireRealName: boolean;
  requireStudentNumber: boolean;
  mode: "direct" | "approval";
  expiresAt: string;
  available: boolean;
  invitationVersion: number;
}

export interface CreateTaskHelpRequestInput {
  projectId: string;
  taskId: string;
  requestId: string;
  expectedVersion: number;
  message: string;
  targetUserId?: string;
  marksTaskBlocked: boolean;
}

export interface CreateTaskHelpRequestData {
  helpRequestId: string;
  state: "open";
  helpVersion: number;
  taskVersion: number;
  taskResumed: false;
}

export interface ResolveTaskHelpRequestInput {
  projectId: string;
  helpRequestId: string;
  requestId: string;
  expectedVersion: number;
}

export interface ResolveTaskHelpRequestData {
  helpRequestId: string;
  state: "resolved";
  helpVersion: number;
  taskVersion: number;
  taskResumed: boolean;
}

export interface RequestUpstreamReworkInput {
  projectId: string;
  downstreamTaskId: string;
  upstreamTaskId: string;
  requestId: string;
  expectedDownstreamVersion: number;
  expectedUpstreamVersion: number;
  requirement: string;
}

export interface RequestUpstreamReworkData {
  reworkRequestId: string;
  state: "pending" | "approved";
  requestVersion: number;
  downstreamTaskVersion: number;
  upstreamTaskVersion: number;
}

export interface ReviewUpstreamReworkInput {
  projectId: string;
  reworkRequestId: string;
  requestId: string;
  expectedVersion: number;
  action: "approve" | "reject";
}

export interface ReviewUpstreamReworkData {
  reworkRequestId: string;
  state: "approved" | "rejected";
  requestVersion: number;
  downstreamTaskVersion: number;
  upstreamTaskVersion: number;
}

export function isCommandSuccess<T>(
  result: CommandResult<T>,
): result is CommandSuccess<T> {
  return result.ok;
}

export function isCommandFailure<T>(
  result: CommandResult<T>,
): result is CommandFailure {
  return !result.ok;
}
