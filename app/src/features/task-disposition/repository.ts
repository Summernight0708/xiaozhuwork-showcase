import { getBackend } from "@/services/backend";

export type TaskDispositionCommand =
  | "cmd_cancel_task"
  | "cmd_abandon_task_responsibility"
  | "cmd_delete_empty_task";
export type FileWithdrawalCommand = "cmd_withdraw_file_version";

export interface DispositionResult {
  ok: boolean;
  code?: string;
  details?: unknown;
  aggregateVersion?: number;
  replayed?: boolean;
  data?: Record<string, unknown>;
}
export async function invokeDisposition(
  command: TaskDispositionCommand | FileWithdrawalCommand,
  params: Record<string, unknown>,
): Promise<DispositionResult> {
  const backend = getBackend();
  if (!backend) throw new Error("无法连接服务端");
  const { data, error } = await (
    backend.client as unknown as {
      rpc: (
        method: string,
        args: Record<string, unknown>,
      ) => Promise<{
        data: DispositionResult | null;
        error: { message: string } | null;
      }>;
    }
  ).rpc(command, params);
  if (error) throw new Error(error.message);
  if (!data || typeof data.ok !== "boolean") throw new Error("服务器响应无效");
  if (!data.ok) throw new Error(data.code ?? "操作未成功，请刷新后重试");
  return data;
}
