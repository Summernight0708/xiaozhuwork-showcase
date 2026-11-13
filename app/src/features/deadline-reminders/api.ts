import type { SupabaseClient } from "@supabase/supabase-js";
import { getBackend } from "@/services/backend";
import {
  DEFAULT_REMINDER_OFFSETS,
  normalizeReminderOffsets,
  type ReminderCommandResult,
  type ReminderPreferences,
} from "./model";

function client(): SupabaseClient {
  const backend = getBackend();
  if (!backend) throw new Error("后端暂不可用");
  // New RPC and table types are generated centrally by workstream G.
  return backend.client as unknown as SupabaseClient;
}

async function unwrapCommand(
  result: PromiseLike<{ data: unknown; error: { message: string } | null }>,
): Promise<ReminderCommandResult> {
  const { data, error } = await result;
  if (error) throw new Error(error.message);
  const payload = data as ReminderCommandResult | null;
  if (!payload) throw new Error("服务器未返回命令结果");
  if (!payload.ok) throw new Error(payload.code ?? "提醒操作失败");
  return payload;
}

export async function loadTaskReminderPreferences(
  projectId: string,
  taskId: string,
): Promise<{ enabled: boolean; offsets: number[]; version: number }> {
  const { data, error } = await client()
    .from("task_reminder_preferences")
    .select("project_id,task_id,recipient_id,enabled,offsets_seconds,version")
    .eq("project_id", projectId)
    .eq("task_id", taskId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  const pref = data as ReminderPreferences | null;
  return {
    enabled: pref?.enabled ?? true,
    offsets: pref?.offsets_seconds ?? [...DEFAULT_REMINDER_OFFSETS],
    version: pref?.version ?? 0,
  };
}

export function saveTaskReminderPreferences(
  projectId: string,
  taskId: string,
  offsets: number[],
  enabled: boolean,
  version: number,
): Promise<ReminderCommandResult> {
  return unwrapCommand(
    client().rpc("cmd_set_task_reminder_preferences", {
      p_project_id: projectId,
      p_task_id: taskId,
      p_offsets_seconds: normalizeReminderOffsets(offsets),
      p_enabled: enabled,
      p_request_id: crypto.randomUUID(),
      p_expected_version: version,
    }),
  );
}

export function sendTaskNudge(
  projectId: string,
  taskId: string,
  taskVersion: number,
): Promise<ReminderCommandResult> {
  return unwrapCommand(
    client().rpc("cmd_send_task_nudge", {
      p_project_id: projectId,
      p_task_id: taskId,
      p_request_id: crypto.randomUUID(),
      p_expected_version: taskVersion,
    }),
  );
}
