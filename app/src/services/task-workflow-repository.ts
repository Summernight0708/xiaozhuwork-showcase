import type { SupabaseClient } from "@supabase/supabase-js";

import type { Database, Tables } from "@/types/database.generated";

type Client = SupabaseClient<Database>;

function assertNoError(error: unknown): asserts error is null {
  if (error) throw new Error("Supabase request failed");
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function assertUuid(value: string, name: string) {
  if (!UUID_PATTERN.test(value)) throw new Error(`Invalid ${name}`);
}

function assertProjectRows<T extends { project_id: string }>(
  rows: T[],
  projectId: string,
): T[] {
  if (rows.some((row) => row.project_id !== projectId)) {
    throw new Error("Cross-project workflow response");
  }
  return rows;
}

export function createTaskWorkflowRepository(client: Client) {
  async function listTaskHelpRequests(projectId: string, taskId: string) {
    assertUuid(projectId, "project id");
    assertUuid(taskId, "task id");
    const { data, error } = await client
      .from("task_help_requests")
      .select("*")
      .eq("project_id", projectId)
      .eq("task_id", taskId)
      .order("created_at", { ascending: false });
    assertNoError(error);
    return assertProjectRows(data ?? [], projectId);
  }

  async function listRelatedUpstreamReworkRequests(
    projectId: string,
    taskId: string,
  ) {
    assertUuid(projectId, "project id");
    assertUuid(taskId, "task id");
    const { data, error } = await client
      .from("upstream_rework_requests")
      .select("*")
      .eq("project_id", projectId)
      .or(`downstream_task_id.eq.${taskId},upstream_task_id.eq.${taskId}`)
      .order("created_at", { ascending: false });
    assertNoError(error);
    return assertProjectRows(data ?? [], projectId);
  }

  return { listTaskHelpRequests, listRelatedUpstreamReworkRequests };
}

export type TaskWorkflowRepository = ReturnType<
  typeof createTaskWorkflowRepository
>;
export type TaskHelpRequestRow = Tables<"task_help_requests">;
export type UpstreamReworkRequestRow = Tables<"upstream_rework_requests">;
