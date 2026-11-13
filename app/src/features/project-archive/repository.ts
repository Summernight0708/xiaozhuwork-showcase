import { getBackend } from "@/services/backend";

export type ArchiveCommandName =
  | "cmd_archive_project"
  | "cmd_restore_project"
  | "cmd_extend_project_retention";

export interface ArchiveCycle {
  id: string;
  project_id: string;
  generation: number;
  archived_at: string;
  retain_until: string;
  recovery_until: string;
  restored_at: string | null;
}

export interface ArchiveCommandResult {
  ok: boolean;
  code?: string;
  currentVersion?: number;
  aggregateVersion?: number;
  replayed?: boolean;
  data?: Record<string, unknown>;
}

type ArchiveRpcClient = {
  rpc: (
    functionName: ArchiveCommandName,
    args: Record<string, unknown>,
  ) => Promise<{
    data: ArchiveCommandResult | null;
    error: { message: string } | null;
  }>;
  from: (table: "project_archive_cycles") => {
    select: (columns: string) => {
      eq: (
        column: string,
        value: string,
      ) => {
        is: (
          column: string,
          value: null,
        ) => {
          maybeSingle: () => Promise<{
            data: ArchiveCycle | null;
            error: { message: string } | null;
          }>;
        };
      };
    };
  };
};

export function archiveRetentionPhase(
  cycle: Pick<ArchiveCycle, "retain_until" | "recovery_until">,
  now = Date.now(),
): "retained" | "recovery_only" | "expired" {
  const retained = Date.parse(cycle.retain_until);
  const recovery = Date.parse(cycle.recovery_until);
  if (!Number.isFinite(retained) || !Number.isFinite(recovery))
    return "expired";
  if (now < retained) return "retained";
  if (now <= recovery) return "recovery_only";
  return "expired";
}

function archiveClient(): ArchiveRpcClient {
  const client = getBackend()?.client;
  if (!client) throw new Error("无法连接服务端");
  // The generated DB types and public command adapter are owned by G.
  return client as unknown as ArchiveRpcClient;
}

export async function loadArchiveCycle(
  projectId: string,
): Promise<ArchiveCycle | null> {
  const { data, error } = await archiveClient()
    .from("project_archive_cycles")
    .select(
      "id,project_id,generation,archived_at,retain_until,recovery_until,restored_at",
    )
    .eq("project_id", projectId)
    .is("restored_at", null)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

async function invokeArchiveCommand(
  name: ArchiveCommandName,
  args: Record<string, unknown>,
): Promise<ArchiveCommandResult> {
  const { data, error } = await archiveClient().rpc(name, args);
  if (error) throw new Error(error.message);
  if (!data) throw new Error("服务端未返回结果");
  return data;
}

export function archiveProject(
  projectId: string,
  version: number,
  reason: string,
  requestId = crypto.randomUUID(),
) {
  return invokeArchiveCommand("cmd_archive_project", {
    p_project_id: projectId,
    p_reason: reason,
    p_request_id: requestId,
    p_expected_version: version,
  });
}

export function restoreProject(
  projectId: string,
  version: number,
  requestId = crypto.randomUUID(),
) {
  return invokeArchiveCommand("cmd_restore_project", {
    p_project_id: projectId,
    p_request_id: requestId,
    p_expected_version: version,
  });
}

export function extendProjectRetention(
  projectId: string,
  version: number,
  days: number,
  requestId = crypto.randomUUID(),
) {
  return invokeArchiveCommand("cmd_extend_project_retention", {
    p_project_id: projectId,
    p_additional_days: days,
    p_request_id: requestId,
    p_expected_version: version,
  });
}
