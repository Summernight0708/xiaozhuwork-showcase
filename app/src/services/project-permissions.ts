/** Pro Phase 2 D: server-authoritative, project-scoped fixed permission templates. */
export const PROJECT_PERMISSION_TEMPLATES = [
  "invitation_coordinator",
  "intake_reviewer",
] as const;

export type ProjectPermissionTemplate =
  (typeof PROJECT_PERMISSION_TEMPLATES)[number];

export const TEMPLATE_DETAILS: Record<
  ProjectPermissionTemplate,
  { name: string; description: string }
> = {
  invitation_coordinator: {
    name: "邀请管理员",
    description: "仅可创建、撤销和续期项目邀请，不可变更成员角色。",
  },
  intake_reviewer: {
    name: "入组审核员",
    description: "仅可审批或拒绝入组申请，仍受原有项目人数限制。",
  },
};

export interface DelegationRecord {
  delegationId: string;
  membershipId: string;
  templateCode: ProjectPermissionTemplate;
  grantedAt: string;
  revokedAt: string | null;
  version: number;
  membershipVersion: number;
  effective: boolean;
}

export interface PermissionSnapshot {
  schemaVersion: 1;
  projectId: string;
  viewerRole: "leader" | "admin" | "member" | "observer";
  capability: { released: boolean; entitled: boolean; effective: boolean };
  delegations: DelegationRecord[];
}

export interface PermissionMember {
  id: string;
  displayName: string;
  role: string;
  version: number;
}

export interface ChangeDelegation {
  projectId: string;
  membershipId: string;
  templateCode: ProjectPermissionTemplate;
  enabled: boolean;
  expectedVersion: number;
  requestId: string;
}

export interface DelegationChangeResult {
  projectId: string;
  membershipId: string;
  templateCode: ProjectPermissionTemplate;
  enabled: boolean;
  changed: boolean;
  membershipVersion: number;
  effective: boolean;
}

export interface PermissionRpcClient {
  rpc: (
    name: string,
    arguments_: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: { message: string } | null }>;
}

export class ProjectPermissionError extends Error {
  constructor(
    public readonly code: string,
    public readonly currentVersion?: number,
  ) {
    super(code);
    this.name = "ProjectPermissionError";
  }
}

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ProjectPermissionError("INVALID_RESPONSE");
  }
  return value as Record<string, unknown>;
}

function requireString(value: unknown): string {
  if (typeof value !== "string") {
    throw new ProjectPermissionError("INVALID_RESPONSE");
  }
  return value;
}

function readEnvelope(value: unknown): Record<string, unknown> {
  const envelope = asRecord(value);
  if (envelope.ok === false) {
    throw new ProjectPermissionError(
      typeof envelope.code === "string" ? envelope.code : "UNKNOWN_ERROR",
      typeof envelope.currentVersion === "number"
        ? envelope.currentVersion
        : undefined,
    );
  }
  if (envelope.ok !== true) {
    throw new ProjectPermissionError("INVALID_RESPONSE");
  }
  return asRecord(envelope.data);
}

function parseTemplate(value: unknown): ProjectPermissionTemplate {
  if (value !== "invitation_coordinator" && value !== "intake_reviewer") {
    throw new ProjectPermissionError("INVALID_RESPONSE");
  }
  return value;
}

function parseDelegation(value: unknown): DelegationRecord {
  const v = asRecord(value);
  if (
    typeof v.version !== "number" ||
    typeof v.membershipVersion !== "number" ||
    typeof v.effective !== "boolean" ||
    !(v.revokedAt === null || typeof v.revokedAt === "string")
  ) {
    throw new ProjectPermissionError("INVALID_RESPONSE");
  }
  return {
    delegationId: requireString(v.delegationId),
    membershipId: requireString(v.membershipId),
    templateCode: parseTemplate(v.templateCode),
    grantedAt: requireString(v.grantedAt),
    revokedAt: v.revokedAt as string | null,
    version: v.version,
    membershipVersion: v.membershipVersion,
    effective: v.effective,
  };
}

export function decodePermissionSnapshot(raw: unknown): PermissionSnapshot {
  const data = readEnvelope(raw);
  const capability = asRecord(data.capability);
  if (
    data.schemaVersion !== 1 ||
    !["leader", "admin", "member", "observer"].includes(
      String(data.viewerRole),
    ) ||
    typeof capability.released !== "boolean" ||
    typeof capability.entitled !== "boolean" ||
    typeof capability.effective !== "boolean" ||
    !Array.isArray(data.delegations)
  ) {
    throw new ProjectPermissionError("INVALID_RESPONSE");
  }
  const delegations = data.delegations.map(parseDelegation);
  return {
    schemaVersion: 1,
    projectId: requireString(data.projectId),
    viewerRole: data.viewerRole as PermissionSnapshot["viewerRole"],
    capability: {
      released: capability.released,
      entitled: capability.entitled,
      effective: capability.effective,
    },
    delegations,
  };
}

export function decodeDelegationChange(raw: unknown): DelegationChangeResult {
  const data = readEnvelope(raw);
  if (
    typeof data.enabled !== "boolean" ||
    typeof data.changed !== "boolean" ||
    typeof data.effective !== "boolean" ||
    typeof data.membershipVersion !== "number"
  ) {
    throw new ProjectPermissionError("INVALID_RESPONSE");
  }
  return {
    projectId: requireString(data.projectId),
    membershipId: requireString(data.membershipId),
    templateCode: parseTemplate(data.templateCode),
    enabled: data.enabled,
    changed: data.changed,
    membershipVersion: data.membershipVersion,
    effective: data.effective,
  };
}

export function delegationAssigned(
  snapshot: PermissionSnapshot,
  membershipId: string,
  templateCode: ProjectPermissionTemplate,
): boolean {
  return snapshot.delegations.some(
    (item) =>
      item.membershipId === membershipId &&
      item.templateCode === templateCode &&
      item.revokedAt === null,
  );
}

export function delegationEffective(
  snapshot: PermissionSnapshot,
  membershipId: string,
  templateCode: ProjectPermissionTemplate,
): boolean {
  return snapshot.delegations.some(
    (item) =>
      item.membershipId === membershipId &&
      item.templateCode === templateCode &&
      item.effective,
  );
}

export function permissionErrorMessage(error: unknown): string {
  if (!(error instanceof ProjectPermissionError)) {
    return "权限操作失败，请检查网络并重试。";
  }
  switch (error.code) {
    case "STALE_VERSION":
      return "成员权限已被其他操作更新，请刷新后重试。";
    case "IDEMPOTENCY_KEY_REUSED":
      return "操作请求已被用于其他内容，请重试。";
    case "CAPABILITY_NOT_AVAILABLE":
      return "高级权限尚未发布。";
    case "CAPABILITY_REQUIRES_PRO":
      return "高级权限仅限 Pro 或宽限期项目。";
    case "NOT_FOUND_OR_NOT_AUTHORIZED":
    case "NOT_AUTHORIZED":
      return "当前身份无权执行此操作，或成员已离开项目。";
    default:
      return "操作未成功（" + error.code + "），请刷新后重试。";
  }
}

export function createProjectPermissionsService(client: PermissionRpcClient) {
  async function invoke(name: string, args: Record<string, unknown>) {
    const { data, error } = await client.rpc(name, args);
    if (error) throw new ProjectPermissionError("TRANSPORT_FAILURE");
    return data;
  }

  return {
    async get(projectId: string): Promise<PermissionSnapshot> {
      return decodePermissionSnapshot(
        await invoke("get_project_permission_delegations", {
          p_project_id: projectId,
        }),
      );
    },
    async set(input: ChangeDelegation): Promise<DelegationChangeResult> {
      return decodeDelegationChange(
        await invoke("cmd_set_project_permission_delegation", {
          p_project_id: input.projectId,
          p_membership_id: input.membershipId,
          p_template_code: input.templateCode,
          p_enabled: input.enabled,
          p_expected_version: input.expectedVersion,
          p_request_id: input.requestId,
        }),
      );
    },
  };
}
