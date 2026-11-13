import type { Database } from "@/types/database.generated";

import type {
  ClaimTaskData,
  ClaimTaskInput,
  CancelTaskPrimaryHandoffInput,
  CommandFailure,
  CommandFailureDetail,
  CommandResult,
  ConfirmContributionReportData,
  ConfirmContributionReportInput,
  CorrectTaskReviewRequestChangesData,
  CorrectTaskReviewRequestChangesInput,
  CreateContributionReportData,
  CreateContributionReportInput,
  CreateProjectData,
  CreateProjectInput,
  CreateProjectInviteData,
  CreateProjectInviteInput,
  CreateTaskData,
  CreateTaskInput,
  EditTaskData,
  EditTaskInput,
  LeaveProjectData,
  LeaveProjectInput,
  LeaveTaskCollaborationInput,
  MarkTaskFileReferenceData,
  MarkTaskFileReferenceInput,
  RemoveProjectMemberData,
  RemoveProjectMemberInput,
  RemoveTaskCollaboratorInput,
  SetTaskDependenciesData,
  SetTaskDependenciesInput,
  SetTaskFileVersionFinalData,
  SetTaskFileVersionFinalInput,
  TransferProjectLeadershipData,
  TransferProjectLeadershipInput,
  UpdateProjectMemberRoleData,
  UpdateProjectMemberRoleInput,
  UpdateProjectSettingsData,
  UpdateProjectSettingsInput,
  DomainErrorCode,
  JoinProjectViaInviteData,
  JoinProjectViaInviteInput,
  PreviewProjectInviteData,
  PreviewProjectInviteInput,
  ProposeTaskChangeData,
  ProposeTaskChangeInput,
  ReserveTaskFileUploadData,
  ReserveTaskFileUploadInput,
  InviteTaskCollaboratorInput,
  RespondToTaskAssignmentData,
  RespondToTaskAssignmentInput,
  RespondToTaskCollaboratorInput,
  TaskCollaboratorCommandData,
  RespondToTaskChangeData,
  RespondToTaskChangeInput,
  ReviewProjectJoinRequestData,
  ReviewProjectJoinRequestInput,
  ReviewTaskSubmissionData,
  ReviewTaskSubmissionInput,
  RenewProjectInviteData,
  RenewProjectInviteInput,
  RevokeProjectInviteData,
  RevokeProjectInviteInput,
  SubmitTaskForReviewData,
  SubmitTaskForReviewInput,
  UpdateTaskProgressData,
  UpdateTaskProgressInput,
  CreateTaskHelpRequestData,
  CreateTaskHelpRequestInput,
  ResolveTaskHelpRequestData,
  ResolveTaskHelpRequestInput,
  RequestUpstreamReworkData,
  RequestUpstreamReworkInput,
  RequestTaskPrimaryHandoffInput,
  RespondTaskPrimaryHandoffInput,
  TaskPrimaryHandoffCommandData,
  UnassignTaskPrimaryData,
  UnassignTaskPrimaryInput,
  ReviewUpstreamReworkData,
  ReviewUpstreamReworkInput,
} from "@/types/commands";

interface RpcResponse {
  data: unknown;
  error: unknown;
}

export type ClientRpcName =
  | "cmd_create_project"
  | "cmd_create_project_invite"
  | "cmd_renew_project_invite"
  | "cmd_revoke_project_invite"
  | "cmd_join_project_via_invite"
  | "cmd_leave_project"
  | "cmd_review_project_join_request"
  | "cmd_create_task"
  | "cmd_create_task_v2"
  | "cmd_claim_task"
  | "cmd_respond_to_task_assignment"
  | "cmd_invite_task_collaborator"
  | "cmd_respond_to_task_collaborator"
  | "cmd_remove_task_collaborator"
  | "cmd_leave_task_collaboration"
  | "cmd_update_task_progress"
  | "cmd_reserve_task_file_upload"
  | "cmd_mark_task_file_reference"
  | "cmd_submit_task_for_review"
  | "cmd_review_task_submission"
  | "cmd_correct_task_review_request_changes"
  | "cmd_request_task_primary_handoff"
  | "cmd_respond_task_primary_handoff"
  | "cmd_cancel_task_primary_handoff"
  | "cmd_unassign_task_primary"
  | "cmd_create_contribution_report"
  | "cmd_confirm_contribution_report"
  | "cmd_update_project_member_role"
  | "cmd_remove_project_member"
  | "cmd_transfer_project_leadership"
  | "cmd_edit_task"
  | "cmd_edit_task_v2"
  | "cmd_propose_task_change"
  | "cmd_propose_task_change_v2"
  | "cmd_respond_to_task_change"
  | "cmd_create_task_help_request"
  | "cmd_resolve_task_help_request"
  | "cmd_request_upstream_rework"
  | "cmd_review_upstream_rework"
  | "cmd_set_task_dependencies"
  | "cmd_set_task_file_version_final"
  | "cmd_update_project_settings"
  | "preview_project_invite";

type GeneratedRpcArgs<Name extends ClientRpcName> =
  Database["public"]["Functions"][Name]["Args"];
type NullableRpcArgs<Name extends ClientRpcName> = {
  [Key in keyof GeneratedRpcArgs<Name>]: GeneratedRpcArgs<Name>[Key] | null;
};
export interface RpcPort {
  rpc<Name extends ClientRpcName>(
    functionName: Name,
    parameters: NullableRpcArgs<Name>,
  ): PromiseLike<RpcResponse>;
}

export class CommandTransportError extends Error {
  readonly requestId: string;
  readonly retryable: boolean;
  readonly diagnosticId: string;

  constructor(requestId: string, retryable: boolean) {
    super("The command could not be completed.");
    this.name = "CommandTransportError";
    this.requestId = requestId;
    this.retryable = retryable;
    this.diagnosticId = `cmd_${newRequestId()}`;
  }
}

export function newRequestId(): string {
  return globalThis.crypto.randomUUID();
}

const DOMAIN_ERROR_CODES = new Set<DomainErrorCode>([
  "UNAUTHENTICATED",
  "NOT_FOUND_OR_NOT_AUTHORIZED",
  "VALIDATION_FAILED",
  "IDEMPOTENCY_KEY_REUSED",
  "INVITE_UNAVAILABLE",
  "INVITE_EXHAUSTED",
  "ALREADY_MEMBER",
  "JOIN_REQUEST_PENDING",
  "TASK_ALREADY_CLAIMED",
  "ASSIGNMENT_NOT_PENDING",
  "STALE_VERSION",
  "NOT_AUTHORIZED",
  "INVALID_TRANSITION",
  "QUOTA_EXCEEDED",
  "ACTIVE_FREE_PROJECT_LIMIT_REACHED",
  "PROJECT_MEMBER_LIMIT_REACHED",
  "CONCURRENT_TASK_LIMIT_REACHED",
  "DDL_NOT_IN_FUTURE",
  "CONFIRMATION_REQUIRED",
  "FEATURE_DISABLED",
  "UNSAFE_FILE_TYPE",
  "SHARE_EXPIRED",
  "FILE_TYPE_NOT_ALLOWED",
  "STORAGE_QUOTA_EXCEEDED",
  "FILE_VALIDATION_FAILED",
  "UPLOAD_NOT_READY",
  "PROJECT_NOT_ACTIVE",
  "REVIEW_NOT_PENDING",
  "REPORT_NOT_READY",
]);

const RETRYABLE_RPC_ERROR_CODES = new Set([
  "40001",
  "40P01",
  "55P03",
  "57014",
  "53300",
  "57P01",
  "57P02",
  "57P03",
]);

function isRetryableRpcError(error: unknown) {
  if (typeof error !== "object" || error === null || Array.isArray(error))
    return false;
  const code = (error as Record<string, unknown>).code;
  if (typeof code !== "string") return false;
  return (
    RETRYABLE_RPC_ERROR_CODES.has(code) ||
    code.startsWith("08") ||
    /^PGRST00[0-3]$/.test(code)
  );
}

type RecordValue = Record<string, unknown>;
type DataDecoder<T> = (value: unknown) => T;
type Validator = ((value: unknown) => unknown) & { optional?: boolean };

function record(value: unknown): RecordValue {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError("Expected an object");
  }
  return value as RecordValue;
}

const stringValue: Validator = (value) => {
  if (typeof value !== "string") throw new TypeError("Expected a string");
  return value;
};

function integerAtLeast(minimum: number): Validator {
  return (value) => {
    if (
      typeof value !== "number" ||
      !Number.isInteger(value) ||
      value < minimum
    ) {
      throw new TypeError(`Expected an integer of at least ${minimum}`);
    }
    return value;
  };
}

const entityVersionValue = integerAtLeast(1);
const nonNegativeIntegerValue = integerAtLeast(0);

const booleanValue: Validator = (value) => {
  if (typeof value !== "boolean") throw new TypeError("Expected a boolean");
  return value;
};

const stringArrayValue: Validator = (value) => {
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    throw new TypeError("Expected a string array");
  }
  return value;
};

function enumValue<const T extends readonly string[]>(allowed: T): Validator {
  return (value) => {
    if (typeof value !== "string" || !allowed.includes(value)) {
      throw new TypeError("Expected an allowed value");
    }
    return value;
  };
}

function optional(validator: Validator): Validator {
  const result: Validator = (value) =>
    value === null ? undefined : validator(value);
  result.optional = true;
  return result;
}

function decodeShape(
  value: unknown,
  shape: Record<string, Validator>,
): RecordValue {
  const source = record(value);
  const decoded: RecordValue = {};
  for (const [key, validator] of Object.entries(shape)) {
    if (source[key] === undefined && validator.optional) continue;
    const normalized = validator(source[key]);
    if (normalized !== undefined) decoded[key] = normalized;
  }
  return decoded;
}

function decodeFailure(value: RecordValue): CommandFailure {
  const code = stringValue(value.code) as string;
  if (!DOMAIN_ERROR_CODES.has(code as DomainErrorCode)) {
    throw new TypeError("Unknown domain error code");
  }

  let details: Record<string, CommandFailureDetail> | undefined;
  if (value.details !== undefined) {
    details = {};
    for (const [key, detail] of Object.entries(record(value.details))) {
      if (
        typeof detail !== "string" &&
        typeof detail !== "number" &&
        typeof detail !== "boolean"
      ) {
        throw new TypeError("Unsafe failure detail");
      }
      details[key] = detail;
    }
  }

  return {
    ok: false,
    code: code as DomainErrorCode,
    requestId: stringValue(value.requestId) as string,
    replayed: booleanValue(value.replayed) as boolean,
    ...(value.field === undefined
      ? {}
      : { field: stringValue(value.field) as string }),
    ...(value.currentVersion === undefined
      ? {}
      : {
          currentVersion: nonNegativeIntegerValue(
            value.currentVersion,
          ) as number,
        }),
    ...(details === undefined ? {} : { details }),
  };
}

function decodeCommandResult<T>(
  value: unknown,
  decodeData: DataDecoder<T>,
): CommandResult<T> {
  const envelope = record(value);
  if (envelope.ok === false) return decodeFailure(envelope);
  if (envelope.ok !== true) throw new TypeError("Invalid command envelope");
  return {
    ok: true,
    data: decodeData(envelope.data),
    requestId: stringValue(envelope.requestId) as string,
    replayed: booleanValue(envelope.replayed) as boolean,
    aggregateType: stringValue(envelope.aggregateType) as string,
    aggregateId: stringValue(envelope.aggregateId) as string,
    aggregateVersion: entityVersionValue(envelope.aggregateVersion) as number,
  };
}

function decoder<T>(shape: Record<string, Validator>): DataDecoder<T> {
  return (value) => decodeShape(value, shape) as T;
}

const decodeCreateProject = decoder<CreateProjectData>({
  projectId: stringValue,
  leaderMembershipId: stringValue,
});
const decodeCreateProjectInvite = decoder<CreateProjectInviteData>({
  invitationId: stringValue,
  token: stringValue,
  expiresAt: stringValue,
  invitationVersion: entityVersionValue,
});
const decodeRenewProjectInvite = decoder<RenewProjectInviteData>({
  invitationId: stringValue,
  expiresAt: stringValue,
  invitationVersion: entityVersionValue,
});
const decodeRevokeProjectInvite = decoder<RevokeProjectInviteData>({
  invitationId: stringValue,
  revokedAt: stringValue,
  canceledJoinRequestCount: nonNegativeIntegerValue,
});
const decodeJoinProjectViaInviteShape = decoder<JoinProjectViaInviteData>({
  projectId: stringValue,
  outcome: enumValue(["joined", "pending_approval"]),
  membershipId: optional(stringValue),
  joinRequestId: optional(stringValue),
  invitationVersion: entityVersionValue,
});
const decodeReviewProjectJoinRequestShape =
  decoder<ReviewProjectJoinRequestData>({
    projectId: stringValue,
    joinRequestId: stringValue,
    state: enumValue(["approved", "rejected"]),
    membershipId: optional(stringValue),
  });

function decodeJoinProjectViaInvite(value: unknown): JoinProjectViaInviteData {
  const data = decodeJoinProjectViaInviteShape(value);
  if (data.outcome === "joined" && data.membershipId === undefined) {
    throw new TypeError("Joined outcome requires a membership");
  }
  if (data.outcome === "pending_approval" && data.joinRequestId === undefined) {
    throw new TypeError("Pending outcome requires a join request");
  }
  return data;
}

function decodeReviewProjectJoinRequest(
  value: unknown,
): ReviewProjectJoinRequestData {
  const data = decodeReviewProjectJoinRequestShape(value);
  if (data.state === "approved" && data.membershipId === undefined) {
    throw new TypeError("Approved state requires a membership");
  }
  return data;
}
const decodeCreateTask = decoder<CreateTaskData>({
  taskId: stringValue,
  taskVersion: entityVersionValue,
  assignmentOfferId: optional(stringValue),
  assignmentOfferVersion: optional(entityVersionValue),
});
const decodeClaimTask = decoder<ClaimTaskData>({
  taskId: stringValue,
  assigneeId: stringValue,
  acceptedAt: stringValue,
});
const decodeRespondToTaskAssignment = decoder<RespondToTaskAssignmentData>({
  taskId: stringValue,
  assignmentOfferId: stringValue,
  outcome: enumValue(["accepted", "rejected"]),
  taskVersion: entityVersionValue,
});
const decodeTaskCollaboratorCommand = decoder<TaskCollaboratorCommandData>({
  taskId: stringValue,
  collaboratorId: stringValue,
  userId: stringValue,
  state: enumValue(["pending", "accepted", "rejected", "removed"]),
  collaboratorVersion: entityVersionValue,
});
const decodeTaskPrimaryHandoffCommand = decoder<TaskPrimaryHandoffCommandData>({
  taskId: stringValue,
  handoffId: stringValue,
  fromUserId: stringValue,
  toUserId: stringValue,
  state: enumValue(["pending", "accepted", "rejected", "canceled"]),
  handoffVersion: entityVersionValue,
  taskVersion: entityVersionValue,
});
const decodeUnassignTaskPrimary = decoder<UnassignTaskPrimaryData>({
  taskId: stringValue,
  taskVersion: entityVersionValue,
  assignmentState: enumValue(["claimable"]),
});
const decodeUpdateTaskProgress = decoder<UpdateTaskProgressData>({
  taskId: stringValue,
  status: enumValue(["in_progress", "blocked"]),
  progressText: stringValue,
  blockedReason: optional(stringValue),
  updatedAt: stringValue,
});
const decodeReserveTaskFileUpload = decoder<ReserveTaskFileUploadData>({
  reservationId: stringValue,
  objectPath: stringValue,
  expiresAt: stringValue,
});
const decodeMarkTaskFileReference = decoder<MarkTaskFileReferenceData>({
  taskId: stringValue,
  fileId: stringValue,
  purpose: enumValue(["reference"]),
  fileVersion: entityVersionValue,
  changed: booleanValue,
});
const decodeSubmitTaskForReview = decoder<SubmitTaskForReviewData>({
  taskId: stringValue,
  reviewRoundId: stringValue,
  roundNumber: entityVersionValue,
  submittedAt: stringValue,
});
const decodeReviewTaskSubmissionShape = decoder<ReviewTaskSubmissionData>({
  taskId: stringValue,
  reviewRoundId: stringValue,
  outcome: enumValue(["approve", "reject", "request_changes"]),
  taskStatus: enumValue(["completed", "in_progress"]),
  reviewedAt: stringValue,
  rejectionReason: optional(stringValue),
});

function decodeReviewTaskSubmission(value: unknown): ReviewTaskSubmissionData {
  const data = decodeReviewTaskSubmissionShape(value);
  if (data.outcome === "approve") {
    if (data.taskStatus !== "completed" || data.rejectionReason !== undefined) {
      throw new TypeError("Approved review payload is inconsistent");
    }
  } else if (
    data.taskStatus !== "in_progress" ||
    data.rejectionReason === undefined
  ) {
    throw new TypeError("Rejected review payload is inconsistent");
  }
  return data;
}
const decodeCorrectTaskReviewRequestChanges =
  decoder<CorrectTaskReviewRequestChangesData>({
    taskId: stringValue,
    sourceReviewRoundId: stringValue,
    reviewRoundId: stringValue,
    roundNumber: entityVersionValue,
    taskVersion: entityVersionValue,
    reviewRoundVersion: entityVersionValue,
  });
const decodeCreateContributionReport = decoder<CreateContributionReportData>({
  projectId: stringValue,
  reportId: stringValue,
  reportVersion: entityVersionValue,
  itemCount: nonNegativeIntegerValue,
  state: enumValue(["draft"]),
});
const decodeConfirmContributionReportShape =
  decoder<ConfirmContributionReportData>({
    projectId: stringValue,
    reportId: stringValue,
    state: enumValue(["draft", "formal"]),
    confirmedCount: nonNegativeIntegerValue,
    eligibleCount: nonNegativeIntegerValue,
    requiredCount: entityVersionValue,
    formalized: booleanValue,
  });

function decodeConfirmContributionReport(
  value: unknown,
): ConfirmContributionReportData {
  const data = decodeConfirmContributionReportShape(value);
  const shouldBeFormal =
    data.confirmedCount >= data.requiredCount &&
    data.requiredCount === Math.floor(data.eligibleCount / 2) + 1;
  if (
    data.confirmedCount > data.eligibleCount ||
    data.formalized !== shouldBeFormal ||
    data.state !== (data.formalized ? "formal" : "draft")
  ) {
    throw new TypeError("Contribution confirmation payload is inconsistent");
  }
  return data;
}
const decodeUpdateProjectMemberRole = decoder<UpdateProjectMemberRoleData>({
  membershipId: stringValue,
  role: enumValue(["admin", "member", "observer"]),
  membershipVersion: entityVersionValue,
  projectVersion: entityVersionValue,
  changed: booleanValue,
});
const decodeRemoveProjectMember = decoder<RemoveProjectMemberData>({
  membershipId: stringValue,
  state: enumValue(["removed"]),
  membershipVersion: entityVersionValue,
  projectVersion: entityVersionValue,
  releasedTaskCount: nonNegativeIntegerValue,
});
const decodeLeaveProject = decoder<LeaveProjectData>({
  membershipId: stringValue,
  state: enumValue(["left"]),
  membershipVersion: entityVersionValue,
  projectVersion: entityVersionValue,
  releasedTaskCount: nonNegativeIntegerValue,
});
const decodeTransferProjectLeadership = decoder<TransferProjectLeadershipData>({
  projectId: stringValue,
  leaderUserId: stringValue,
  leaderMembershipId: stringValue,
  projectVersion: entityVersionValue,
});
const decodeEditTask = decoder<EditTaskData>({
  taskId: stringValue,
  taskVersion: entityVersionValue,
  changed: booleanValue,
  title: stringValue,
  description: optional(stringValue),
  deadlineAt: stringValue,
  weight: optional(nonNegativeIntegerValue),
  requiredSubmissionFileTypes: optional(stringArrayValue),
});
const decodeProposeTaskChange = decoder<ProposeTaskChangeData>({
  proposalId: stringValue,
  taskId: stringValue,
  state: enumValue(["pending"]),
  proposalVersion: entityVersionValue,
  createdAt: stringValue,
});
const decodeRespondToTaskChange = decoder<RespondToTaskChangeData>({
  proposalId: stringValue,
  taskId: stringValue,
  state: enumValue(["approved", "rejected"]),
  proposalVersion: entityVersionValue,
  taskVersion: entityVersionValue,
  decidedAt: stringValue,
  decisionReason: optional(stringValue),
});
const decodeCreateTaskHelpRequest = decoder<CreateTaskHelpRequestData>({
  helpRequestId: stringValue,
  state: enumValue(["open"]),
  helpVersion: entityVersionValue,
  taskVersion: entityVersionValue,
  taskResumed: booleanValue,
});
const decodeResolveTaskHelpRequest = decoder<ResolveTaskHelpRequestData>({
  helpRequestId: stringValue,
  state: enumValue(["resolved"]),
  helpVersion: entityVersionValue,
  taskVersion: entityVersionValue,
  taskResumed: booleanValue,
});
const decodeRequestUpstreamRework = decoder<RequestUpstreamReworkData>({
  reworkRequestId: stringValue,
  state: enumValue(["pending", "approved"]),
  requestVersion: entityVersionValue,
  downstreamTaskVersion: entityVersionValue,
  upstreamTaskVersion: entityVersionValue,
});
const decodeReviewUpstreamRework = decoder<ReviewUpstreamReworkData>({
  reworkRequestId: stringValue,
  state: enumValue(["approved", "rejected"]),
  requestVersion: entityVersionValue,
  downstreamTaskVersion: entityVersionValue,
  upstreamTaskVersion: entityVersionValue,
});
const decodeSetTaskDependencies = decoder<SetTaskDependenciesData>({
  taskId: stringValue,
  taskVersion: entityVersionValue,
  changed: booleanValue,
  upstreamTaskIds: stringArrayValue,
});
const decodeSetTaskFileVersionFinal = decoder<SetTaskFileVersionFinalData>({
  fileVersionId: stringValue,
  fileId: stringValue,
  taskId: stringValue,
  isFinal: booleanValue,
  designationVersion: entityVersionValue,
  changed: booleanValue,
});
const decodeUpdateProjectSettings = decoder<UpdateProjectSettingsData>({
  projectId: stringValue,
  projectVersion: entityVersionValue,
  changed: booleanValue,
});

const decodePreviewProjectInvite = decoder<PreviewProjectInviteData>({
  projectId: stringValue,
  projectName: stringValue,
  projectDeadlineAt: stringValue,
  requireRealName: booleanValue,
  requireStudentNumber: booleanValue,
  mode: enumValue(["direct", "approval"]),
  expiresAt: stringValue,
  available: booleanValue,
  invitationVersion: entityVersionValue,
});

export interface CommandAdapter {
  createProject(
    input: CreateProjectInput,
  ): Promise<CommandResult<CreateProjectData>>;
  createProjectInvite(
    input: CreateProjectInviteInput,
  ): Promise<CommandResult<CreateProjectInviteData>>;
  renewProjectInvite(
    input: RenewProjectInviteInput,
  ): Promise<CommandResult<RenewProjectInviteData>>;
  revokeProjectInvite(
    input: RevokeProjectInviteInput,
  ): Promise<CommandResult<RevokeProjectInviteData>>;
  joinProjectViaInvite(
    input: JoinProjectViaInviteInput,
  ): Promise<CommandResult<JoinProjectViaInviteData>>;
  reviewProjectJoinRequest(
    input: ReviewProjectJoinRequestInput,
  ): Promise<CommandResult<ReviewProjectJoinRequestData>>;
  createTask(input: CreateTaskInput): Promise<CommandResult<CreateTaskData>>;
  claimTask(input: ClaimTaskInput): Promise<CommandResult<ClaimTaskData>>;
  respondToTaskAssignment(
    input: RespondToTaskAssignmentInput,
  ): Promise<CommandResult<RespondToTaskAssignmentData>>;
  inviteTaskCollaborator(
    input: InviteTaskCollaboratorInput,
  ): Promise<CommandResult<TaskCollaboratorCommandData>>;
  respondToTaskCollaborator(
    input: RespondToTaskCollaboratorInput,
  ): Promise<CommandResult<TaskCollaboratorCommandData>>;
  removeTaskCollaborator(
    input: RemoveTaskCollaboratorInput,
  ): Promise<CommandResult<TaskCollaboratorCommandData>>;
  leaveTaskCollaboration(
    input: LeaveTaskCollaborationInput,
  ): Promise<CommandResult<TaskCollaboratorCommandData>>;
  updateTaskProgress(
    input: UpdateTaskProgressInput,
  ): Promise<CommandResult<UpdateTaskProgressData>>;
  reserveTaskFileUpload(
    input: ReserveTaskFileUploadInput,
  ): Promise<CommandResult<ReserveTaskFileUploadData>>;
  markTaskFileReference(
    input: MarkTaskFileReferenceInput,
  ): Promise<CommandResult<MarkTaskFileReferenceData>>;
  submitTaskForReview(
    input: SubmitTaskForReviewInput,
  ): Promise<CommandResult<SubmitTaskForReviewData>>;
  reviewTaskSubmission(
    input: ReviewTaskSubmissionInput,
  ): Promise<CommandResult<ReviewTaskSubmissionData>>;
  correctTaskReviewRequestChanges(
    input: CorrectTaskReviewRequestChangesInput,
  ): Promise<CommandResult<CorrectTaskReviewRequestChangesData>>;
  requestTaskPrimaryHandoff(
    input: RequestTaskPrimaryHandoffInput,
  ): Promise<CommandResult<TaskPrimaryHandoffCommandData>>;
  respondTaskPrimaryHandoff(
    input: RespondTaskPrimaryHandoffInput,
  ): Promise<CommandResult<TaskPrimaryHandoffCommandData>>;
  cancelTaskPrimaryHandoff(
    input: CancelTaskPrimaryHandoffInput,
  ): Promise<CommandResult<TaskPrimaryHandoffCommandData>>;
  unassignTaskPrimary(
    input: UnassignTaskPrimaryInput,
  ): Promise<CommandResult<UnassignTaskPrimaryData>>;
  createContributionReport(
    input: CreateContributionReportInput,
  ): Promise<CommandResult<CreateContributionReportData>>;
  confirmContributionReport(
    input: ConfirmContributionReportInput,
  ): Promise<CommandResult<ConfirmContributionReportData>>;
  updateProjectMemberRole(
    input: UpdateProjectMemberRoleInput,
  ): Promise<CommandResult<UpdateProjectMemberRoleData>>;
  removeProjectMember(
    input: RemoveProjectMemberInput,
  ): Promise<CommandResult<RemoveProjectMemberData>>;
  leaveProject(
    input: LeaveProjectInput,
  ): Promise<CommandResult<LeaveProjectData>>;
  transferProjectLeadership(
    input: TransferProjectLeadershipInput,
  ): Promise<CommandResult<TransferProjectLeadershipData>>;
  editTask(input: EditTaskInput): Promise<CommandResult<EditTaskData>>;
  proposeTaskChange(
    input: ProposeTaskChangeInput,
  ): Promise<CommandResult<ProposeTaskChangeData>>;
  respondToTaskChange(
    input: RespondToTaskChangeInput,
  ): Promise<CommandResult<RespondToTaskChangeData>>;
  createTaskHelpRequest(
    input: CreateTaskHelpRequestInput,
  ): Promise<CommandResult<CreateTaskHelpRequestData>>;
  resolveTaskHelpRequest(
    input: ResolveTaskHelpRequestInput,
  ): Promise<CommandResult<ResolveTaskHelpRequestData>>;
  requestUpstreamRework(
    input: RequestUpstreamReworkInput,
  ): Promise<CommandResult<RequestUpstreamReworkData>>;
  reviewUpstreamRework(
    input: ReviewUpstreamReworkInput,
  ): Promise<CommandResult<ReviewUpstreamReworkData>>;
  setTaskDependencies(
    input: SetTaskDependenciesInput,
  ): Promise<CommandResult<SetTaskDependenciesData>>;
  setTaskFileVersionFinal(
    input: SetTaskFileVersionFinalInput,
  ): Promise<CommandResult<SetTaskFileVersionFinalData>>;
  updateProjectSettings(
    input: UpdateProjectSettingsInput,
  ): Promise<CommandResult<UpdateProjectSettingsData>>;
  previewProjectInvite(
    input: PreviewProjectInviteInput,
  ): Promise<PreviewProjectInviteData>;
}

export function createCommandAdapter(port: RpcPort): CommandAdapter {
  async function execute<T, Name extends ClientRpcName>(
    functionName: Name,
    parameters: NullableRpcArgs<Name>,
    requestId: string,
    decodeData: DataDecoder<T>,
  ): Promise<CommandResult<T>> {
    let response: RpcResponse;
    try {
      response = await port.rpc(functionName, parameters);
    } catch {
      throw new CommandTransportError(requestId, true);
    }
    if (response.error !== null) {
      throw new CommandTransportError(
        requestId,
        isRetryableRpcError(response.error),
      );
    }
    try {
      return decodeCommandResult(response.data, decodeData);
    } catch {
      throw new CommandTransportError(requestId, false);
    }
  }

  return createMethods(port, execute);
}

type Execute = <T, Name extends ClientRpcName>(
  functionName: Name,
  parameters: NullableRpcArgs<Name>,
  requestId: string,
  decodeData: DataDecoder<T>,
) => Promise<CommandResult<T>>;

function createMethods(port: RpcPort, execute: Execute): CommandAdapter {
  return {
    createProject: (input) =>
      execute(
        "cmd_create_project",
        {
          p_request_id: input.requestId,
          p_allow_member_task_creation: input.allowMemberTaskCreation ?? true,
          p_expected_version: input.expectedVersion,
          p_name: input.name,
          p_course_name: input.courseName ?? null,
          p_description: input.description ?? null,
          p_deadline_at: input.deadlineAt,
          p_timezone: input.timezone ?? null,
          p_contribution_mode: input.contributionMode ?? null,
          p_require_real_name: input.requireRealName ?? null,
          p_require_student_number: input.requireStudentNumber ?? null,
          p_start_at: input.startAt ?? null,
        },
        input.requestId,
        decodeCreateProject,
      ),
    createProjectInvite: (input) =>
      execute(
        "cmd_create_project_invite",
        {
          p_project_id: input.projectId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_mode: input.mode,
          p_expires_in_days: input.expiresInDays ?? null,
          p_max_uses: input.maxUses ?? null,
        },
        input.requestId,
        decodeCreateProjectInvite,
      ),
    renewProjectInvite: (input) =>
      execute(
        "cmd_renew_project_invite",
        {
          p_project_id: input.projectId,
          p_invitation_id: input.invitationId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_extend_days: input.extendDays ?? 7,
        },
        input.requestId,
        decodeRenewProjectInvite,
      ),
    revokeProjectInvite: (input) =>
      execute(
        "cmd_revoke_project_invite",
        {
          p_project_id: input.projectId,
          p_invitation_id: input.invitationId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeRevokeProjectInvite,
      ),
    joinProjectViaInvite: (input) =>
      execute(
        "cmd_join_project_via_invite",
        {
          p_token: input.token,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeJoinProjectViaInvite,
      ),
    reviewProjectJoinRequest: (input) =>
      execute(
        "cmd_review_project_join_request",
        {
          p_project_id: input.projectId,
          p_join_request_id: input.joinRequestId,
          p_action: input.action,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeReviewProjectJoinRequest,
      ),
    createTask: (input) =>
      execute(
        "cmd_create_task_v2",
        {
          p_project_id: input.projectId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_title: input.title,
          p_description: input.description ?? null,
          p_deadline_at: input.deadlineAt,
          p_weight: input.weight ?? null,
          p_assignment_mode: input.assignmentMode,
          p_assignee_id: input.assigneeId ?? null,
          p_required_submission_file_types:
            input.requiredSubmissionFileTypes ??
            (input.requiredSubmissionFileType
              ? [input.requiredSubmissionFileType]
              : []),
          p_requires_review: input.requiresReview ?? true,
        },
        input.requestId,
        decodeCreateTask,
      ),
    claimTask: (input) =>
      execute(
        "cmd_claim_task",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeClaimTask,
      ),
    respondToTaskAssignment: (input) =>
      execute(
        "cmd_respond_to_task_assignment",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_assignment_offer_id: input.assignmentOfferId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_action: input.action,
        },
        input.requestId,
        decodeRespondToTaskAssignment,
      ),
    inviteTaskCollaborator: (input) =>
      execute(
        "cmd_invite_task_collaborator",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_user_id: input.userId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeTaskCollaboratorCommand,
      ),
    respondToTaskCollaborator: (input) =>
      execute(
        "cmd_respond_to_task_collaborator",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_collaborator_id: input.collaboratorId,
          p_action: input.action,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeTaskCollaboratorCommand,
      ),
    removeTaskCollaborator: (input) =>
      execute(
        "cmd_remove_task_collaborator",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_collaborator_id: input.collaboratorId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeTaskCollaboratorCommand,
      ),
    leaveTaskCollaboration: (input) =>
      execute(
        "cmd_leave_task_collaboration",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_collaborator_id: input.collaboratorId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeTaskCollaboratorCommand,
      ),
    updateTaskProgress: (input) =>
      execute(
        "cmd_update_task_progress",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_status: input.status,
          p_progress_text: input.progressText,
          p_blocked_reason: input.blockedReason ?? null,
        },
        input.requestId,
        decodeUpdateTaskProgress,
      ),
    reserveTaskFileUpload: (input) =>
      execute(
        "cmd_reserve_task_file_upload",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_mode: input.mode,
          p_target_file_id: input.targetFileId ?? null,
          p_original_name: input.originalName,
          p_declared_mime_type: input.declaredMimeType,
          p_declared_size_bytes: input.declaredSizeBytes,
        },
        input.requestId,
        decodeReserveTaskFileUpload,
      ),
    markTaskFileReference: (input) =>
      execute(
        "cmd_mark_task_file_reference",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_file_id: input.fileId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeMarkTaskFileReference,
      ),
    submitTaskForReview: (input) =>
      execute(
        "cmd_submit_task_for_review",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_submission_text: input.submissionText ?? null,
          p_file_version_ids: input.fileVersionIds,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeSubmitTaskForReview,
      ),
    reviewTaskSubmission: (input) =>
      execute(
        "cmd_review_task_submission",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_review_round_id: input.reviewRoundId,
          p_action: input.action,
          p_rejection_reason: input.rejectionReason ?? null,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeReviewTaskSubmission,
      ),
    correctTaskReviewRequestChanges: (input) =>
      execute(
        "cmd_correct_task_review_request_changes",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_review_round_id: input.reviewRoundId,
          p_request_id: input.requestId,
          p_expected_task_version: input.expectedTaskVersion,
          p_expected_review_version: input.expectedReviewVersion,
        },
        input.requestId,
        decodeCorrectTaskReviewRequestChanges,
      ),
    requestTaskPrimaryHandoff: (input) =>
      execute(
        "cmd_request_task_primary_handoff",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_target_user_id: input.targetUserId,
          p_request_id: input.requestId,
          p_expected_task_version: input.expectedTaskVersion,
        },
        input.requestId,
        decodeTaskPrimaryHandoffCommand,
      ),
    respondTaskPrimaryHandoff: (input) =>
      execute(
        "cmd_respond_task_primary_handoff",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_handoff_id: input.handoffId,
          p_action: input.action,
          p_request_id: input.requestId,
          p_expected_handoff_version: input.expectedHandoffVersion,
          p_expected_task_version: input.expectedTaskVersion,
        },
        input.requestId,
        decodeTaskPrimaryHandoffCommand,
      ),
    cancelTaskPrimaryHandoff: (input) =>
      execute(
        "cmd_cancel_task_primary_handoff",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_handoff_id: input.handoffId,
          p_request_id: input.requestId,
          p_expected_handoff_version: input.expectedHandoffVersion,
          p_expected_task_version: input.expectedTaskVersion,
        },
        input.requestId,
        decodeTaskPrimaryHandoffCommand,
      ),
    unassignTaskPrimary: (input) =>
      execute(
        "cmd_unassign_task_primary",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_request_id: input.requestId,
          p_expected_task_version: input.expectedTaskVersion,
        },
        input.requestId,
        decodeUnassignTaskPrimary,
      ),
    updateProjectMemberRole: (input) =>
      execute(
        "cmd_update_project_member_role",
        {
          p_project_id: input.projectId,
          p_membership_id: input.membershipId,
          p_target_role: input.targetRole,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeUpdateProjectMemberRole,
      ),
    removeProjectMember: (input) =>
      execute(
        "cmd_remove_project_member",
        {
          p_project_id: input.projectId,
          p_membership_id: input.membershipId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeRemoveProjectMember,
      ),
    leaveProject: (input) =>
      execute(
        "cmd_leave_project",
        {
          p_project_id: input.projectId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeLeaveProject,
      ),
    transferProjectLeadership: (input) =>
      execute(
        "cmd_transfer_project_leadership",
        {
          p_project_id: input.projectId,
          p_target_membership_id: input.targetMembershipId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeTransferProjectLeadership,
      ),
    editTask: (input) =>
      execute(
        "cmd_edit_task_v2",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_title: input.title,
          p_description: input.description ?? null,
          p_deadline_at: input.deadlineAt,
          p_weight: input.weight ?? null,
          p_required_submission_file_types:
            input.requiredSubmissionFileTypes ??
            (input.requiredSubmissionFileType
              ? [input.requiredSubmissionFileType]
              : []),
        },
        input.requestId,
        decodeEditTask,
      ),
    proposeTaskChange: (input) =>
      execute(
        "cmd_propose_task_change_v2",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_deadline_at: input.deadlineAt,
          p_weight: input.weight ?? null,
          p_request_id: input.requestId,
          p_expected_task_version: input.expectedTaskVersion,
          p_required_submission_file_types:
            input.requiredSubmissionFileTypes ??
            (input.requiredSubmissionFileType
              ? [input.requiredSubmissionFileType]
              : []),
        },
        input.requestId,
        decodeProposeTaskChange,
      ),
    respondToTaskChange: (input) =>
      execute(
        "cmd_respond_to_task_change",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_proposal_id: input.proposalId,
          p_action: input.action,
          p_rejection_reason: input.rejectionReason ?? null,
          p_request_id: input.requestId,
          p_expected_proposal_version: input.expectedProposalVersion,
        },
        input.requestId,
        decodeRespondToTaskChange,
      ),
    createTaskHelpRequest: (input) =>
      execute(
        "cmd_create_task_help_request",
        {
          p_project_id: input.projectId,
          p_task_id: input.taskId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_message: input.message,
          p_target_user_id: input.targetUserId ?? null,
          p_marks_task_blocked: input.marksTaskBlocked,
        },
        input.requestId,
        decodeCreateTaskHelpRequest,
      ),
    resolveTaskHelpRequest: (input) =>
      execute(
        "cmd_resolve_task_help_request",
        {
          p_project_id: input.projectId,
          p_help_request_id: input.helpRequestId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeResolveTaskHelpRequest,
      ),
    requestUpstreamRework: (input) =>
      execute(
        "cmd_request_upstream_rework",
        {
          p_project_id: input.projectId,
          p_downstream_task_id: input.downstreamTaskId,
          p_upstream_task_id: input.upstreamTaskId,
          p_request_id: input.requestId,
          p_expected_downstream_version: input.expectedDownstreamVersion,
          p_expected_upstream_version: input.expectedUpstreamVersion,
          p_requirement: input.requirement,
        },
        input.requestId,
        decodeRequestUpstreamRework,
      ),
    reviewUpstreamRework: (input) =>
      execute(
        "cmd_review_upstream_rework",
        {
          p_project_id: input.projectId,
          p_rework_request_id: input.reworkRequestId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_action: input.action,
        },
        input.requestId,
        decodeReviewUpstreamRework,
      ),
    setTaskDependencies: (input) =>
      execute(
        "cmd_set_task_dependencies",
        {
          p_project_id: input.projectId,
          p_downstream_task_id: input.downstreamTaskId,
          p_upstream_task_ids: input.upstreamTaskIds,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeSetTaskDependencies,
      ),
    setTaskFileVersionFinal: (input) =>
      execute(
        "cmd_set_task_file_version_final",
        {
          p_project_id: input.projectId,
          p_file_version_id: input.fileVersionId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_is_final: input.isFinal,
        },
        input.requestId,
        decodeSetTaskFileVersionFinal,
      ),
    updateProjectSettings: (input) =>
      execute(
        "cmd_update_project_settings",
        {
          p_project_id: input.projectId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
          p_name: input.name,
          p_course_name: input.courseName ?? null,
          p_description: input.description ?? null,
          p_deadline_at: input.deadlineAt,
          p_timezone: input.timezone,
          p_contribution_mode: input.contributionMode,
          p_auto_penalty_enabled: input.autoPenaltyEnabled,
          p_require_real_name: input.requireRealName,
          ...(input.allowMemberTaskCreation === undefined
            ? {}
            : { p_allow_member_task_creation: input.allowMemberTaskCreation }),
          p_require_student_number: input.requireStudentNumber,
          p_start_at: input.startAt ?? null,
        },
        input.requestId,
        decodeUpdateProjectSettings,
      ),
    createContributionReport: (input) =>
      execute(
        "cmd_create_contribution_report",
        {
          p_project_id: input.projectId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeCreateContributionReport,
      ),
    confirmContributionReport: (input) =>
      execute(
        "cmd_confirm_contribution_report",
        {
          p_project_id: input.projectId,
          p_report_id: input.reportId,
          p_request_id: input.requestId,
          p_expected_version: input.expectedVersion,
        },
        input.requestId,
        decodeConfirmContributionReport,
      ),
    async previewProjectInvite(input) {
      const requestId = newRequestId();
      let response: RpcResponse;
      try {
        response = await port.rpc("preview_project_invite", {
          p_token: input.token,
        });
      } catch {
        throw new CommandTransportError(requestId, true);
      }
      if (response.error !== null) {
        throw new CommandTransportError(
          requestId,
          isRetryableRpcError(response.error),
        );
      }
      try {
        return decodePreviewProjectInvite(response.data);
      } catch {
        throw new CommandTransportError(requestId, false);
      }
    },
  };
}
