import { getBackend } from "@/services/backend";

export type AccountLifecycleState =
  "active" | "pending" | "canceled" | "blocked" | "redacted";

export interface AccountLifecycleStatus {
  state: AccountLifecycleState;
  version: number;
  generation?: number;
  requestedAt?: string;
  cancelUntil?: string;
  authRevokedAt?: string | null;
  redactedAt?: string | null;
}

type CommandResponse = {
  ok: boolean;
  code?: string;
  details?: { reason?: string };
  data?: AccountLifecycleStatus;
  aggregateVersion?: number;
  replayed?: boolean;
};

type RpcResult = { data: unknown; error: { message: string } | null };
type Rpc = (name: string, args?: Record<string, unknown>) => Promise<RpcResult>;

function clientRpc(): Rpc {
  const backend = getBackend();
  if (!backend) throw new Error("后端服务尚未配置");
  // G owns the generated Database type and will replace this typed adapter.
  return backend.client.rpc.bind(backend.client) as unknown as Rpc;
}

export function explainAccountDeletionError(result: CommandResponse): string {
  if (result.code === "REAUTHENTICATION_REQUIRED")
    return "登录凭据已失效，请重新登录原账号后重试";
  if (result.code === "ACCOUNT_DELETION_BLOCKED") {
    return result.details?.reason ?? "请先完成项目责任交接或身份恢复";
  }
  if (result.code === "STALE_VERSION") return "账号状态已变化，请刷新后重试";
  if (result.code === "RETENTION_WINDOW_EXPIRED") return "注销撤销期限已结束";
  if (result.code === "INVALID_TRANSITION") return "当前状态不允许执行此操作";
  if (result.code === "NOT_FOUND_OR_NOT_AUTHORIZED") return "无权操作此账号";
  if (result.code === "IDEMPOTENCY_KEY_REUSED")
    return "操作凭据重复，请刷新后重试";
  return result.code ?? "操作失败，请稍后重试";
}

function readResult(value: unknown): CommandResponse {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("服务器返回了无效的账号状态");
  }
  const result = value as CommandResponse;
  if (typeof result.ok !== "boolean") throw new Error("账号状态响应无效");
  return result;
}

async function rpc(name: string, args?: Record<string, unknown>) {
  const { data, error } = await clientRpc()(name, args);
  if (error) throw new Error(error.message);
  const result = readResult(data);
  if (!result.ok) throw new Error(explainAccountDeletionError(result));
  return result;
}

export async function getAccountLifecycleStatus(): Promise<AccountLifecycleStatus> {
  const result = await rpc("get_account_lifecycle_status");
  if (
    !result.data ||
    !["active", "pending", "canceled", "blocked", "redacted"].includes(
      result.data.state,
    ) ||
    !Number.isSafeInteger(result.data.version) ||
    result.data.version < 0
  )
    throw new Error("账号状态缺失或无效，请重新读取");
  return result.data;
}

export async function requestAccountDeletion(
  requestId: string,
  expectedVersion: number,
): Promise<CommandResponse> {
  return rpc("cmd_request_account_deletion", {
    p_request_id: requestId,
    p_expected_version: expectedVersion,
  });
}

export async function cancelAccountDeletion(
  requestId: string,
  expectedVersion: number,
): Promise<CommandResponse> {
  return rpc("cmd_cancel_account_deletion", {
    p_request_id: requestId,
    p_expected_version: expectedVersion,
  });
}

export function mayCancelDeletion(
  status: AccountLifecycleStatus,
  now: number,
): boolean {
  return (
    status.state === "pending" &&
    !status.authRevokedAt &&
    !status.redactedAt &&
    !!status.cancelUntil &&
    Date.parse(status.cancelUntil) > now
  );
}
