import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.generated";
import type {
  EvidenceCommandResult,
  EvidencePage,
  ExternalEvidence,
  ExternalEvidenceRepository,
  ExternalEvidenceRevision,
} from "./types";

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new TypeError("Invalid evidence response");
  return value as Record<string, unknown>;
}
function text(value: unknown): string {
  if (typeof value !== "string") throw new TypeError("Invalid evidence text");
  return value;
}
function nullable(value: unknown): string | null {
  return value === null ? null : text(value);
}
function version(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1)
    throw new TypeError("Invalid evidence version");
  return value;
}
function pageRange(page: EvidencePage = { offset: 0 }): [number, number] {
  const { offset, limit = 100 } = page;
  if (
    !Number.isSafeInteger(offset) ||
    offset < 0 ||
    !Number.isSafeInteger(limit) ||
    limit < 1 ||
    limit > 200 ||
    !Number.isSafeInteger(offset + limit)
  ) {
    throw new RangeError(
      "Evidence page requires offset >= 0 and limit between 1 and 200",
    );
  }
  return [offset, offset + limit - 1];
}
export function decodeEvidence(raw: unknown): ExternalEvidence {
  const row = record(raw);
  return {
    id: text(row.id),
    projectId: text(row.project_id),
    taskId: text(row.task_id),
    httpsUrl: text(row.https_url),
    host: text(row.host),
    description: text(row.description),
    submittedBy: nullable(row.submitted_by),
    createdAt: text(row.created_at),
    updatedAt: text(row.updated_at),
    revokedAt: nullable(row.revoked_at),
    revokedBy: nullable(row.revoked_by),
    version: version(row.version),
  };
}
function decodeRevision(raw: unknown): ExternalEvidenceRevision {
  const row = record(raw);
  if (row.action !== "updated" && row.action !== "removed")
    throw new TypeError("Invalid evidence revision action");
  return {
    id: text(row.id),
    projectId: text(row.project_id),
    taskId: text(row.task_id),
    evidenceId: text(row.evidence_id),
    httpsUrl: text(row.https_url),
    host: text(row.host),
    description: text(row.description),
    submittedBy: nullable(row.submitted_by),
    evidenceCreatedAt: text(row.evidence_created_at),
    evidenceUpdatedAt: text(row.evidence_updated_at),
    version: version(row.version),
    action: row.action,
    changedBy: nullable(row.changed_by),
    changedAt: text(row.changed_at),
    requestId: text(row.request_id),
    commandRequestId: text(row.command_request_id),
    occurrenceKey: text(row.occurrence_key),
  };
}
export function decodeEvidenceCommand(raw: unknown): EvidenceCommandResult {
  const row = record(raw);
  if (typeof row.replayed !== "boolean")
    throw new TypeError("Invalid replay marker");
  const meta = { requestId: text(row.requestId), replayed: row.replayed };
  if (row.ok === false)
    return {
      ...meta,
      ok: false,
      code: text(row.code),
      ...(row.field === undefined ? {} : { field: text(row.field) }),
      ...(row.currentVersion === undefined
        ? {}
        : { currentVersion: version(row.currentVersion) }),
      ...(row.details === undefined ? {} : { details: row.details }),
    };
  if (
    row.ok !== true ||
    (row.aggregateType !== "task" && row.aggregateType !== "external_evidence")
  ) {
    throw new TypeError("Invalid evidence command envelope");
  }
  const data = record(row.data);
  return {
    ...meta,
    ok: true,
    aggregateType: row.aggregateType,
    aggregateId: text(row.aggregateId),
    aggregateVersion: version(row.aggregateVersion),
    data: {
      evidenceId: text(data.evidenceId),
      taskId: text(data.taskId),
      taskVersion: version(data.taskVersion),
      evidenceVersion: version(data.evidenceVersion),
      revokedAt: nullable(data.revokedAt),
    },
  };
}

/** Temporary local typing seam until G regenerates the shared Database type. */
export function createExternalEvidenceRepository(
  client: SupabaseClient<Database>,
): ExternalEvidenceRepository {
  const evidenceClient = client as unknown as SupabaseClient;
  async function command(name: string, args: Record<string, unknown>) {
    const { data, error } = await evidenceClient.rpc(name, args);
    if (error) throw error; // Caller retains the SAME request ID and payload for transport retries.
    return decodeEvidenceCommand(data);
  }
  return {
    async list(projectId, taskId, page) {
      const range = pageRange(page);
      const { data, error } = await evidenceClient
        .from("task_external_evidence")
        .select("*")
        .eq("project_id", projectId)
        .eq("task_id", taskId)
        .order("created_at")
        .order("id")
        .range(...range);
      if (error) throw error;
      return (data ?? []).map(decodeEvidence);
    },
    async revisions(projectId, evidenceId, page) {
      const range = pageRange(page);
      const { data, error } = await evidenceClient
        .from("task_external_evidence_revisions")
        .select("*")
        .eq("project_id", projectId)
        .eq("evidence_id", evidenceId)
        .order("version", { ascending: false })
        .range(...range);
      if (error) throw error;
      return (data ?? []).map(decodeRevision);
    },
    create: (input) =>
      command("cmd_create_external_evidence", {
        p_project_id: input.projectId,
        p_task_id: input.taskId,
        p_https_url: input.httpsUrl,
        p_description: input.description,
        p_request_id: input.requestId,
        p_expected_version: input.expectedVersion,
      }),
    update: (input) =>
      command("cmd_update_external_evidence", {
        p_project_id: input.projectId,
        p_evidence_id: input.evidenceId,
        p_https_url: input.httpsUrl,
        p_description: input.description,
        p_request_id: input.requestId,
        p_expected_version: input.expectedVersion,
      }),
    remove: (input) =>
      command("cmd_remove_external_evidence", {
        p_project_id: input.projectId,
        p_evidence_id: input.evidenceId,
        p_request_id: input.requestId,
        p_expected_version: input.expectedVersion,
      }),
  };
}
