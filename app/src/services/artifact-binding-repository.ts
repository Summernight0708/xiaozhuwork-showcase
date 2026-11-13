import type { SupabaseClient } from "@supabase/supabase-js";

import type {
  ArtifactBindingStrength,
  ArtifactBindingState,
  FormalArtifactVersion,
  UpstreamArtifact,
  UpstreamArtifactsSnapshot,
} from "@/domain/artifact-binding";
import type { Database } from "@/types/database.generated";

export type ArtifactBindingCommandResult =
  | {
      ok: true;
      data: {
        bindingId: string;
        downstreamTaskId: string;
        fileVersionId: string;
        strength: ArtifactBindingStrength;
        bindingVersion: number;
        changed: boolean;
      };
      requestId?: string;
      replayed?: boolean;
    }
  | {
      ok: false;
      code: string;
      field?: string;
      currentVersion?: number;
      requestId?: string;
      replayed?: boolean;
    };

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError("Expected an object");
  }
  return value as Record<string, unknown>;
}

function stringValue(value: unknown, label: string) {
  if (typeof value !== "string") throw new TypeError(`Invalid ${label}`);
  return value;
}

function numberValue(value: unknown, label: string) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`Invalid ${label}`);
  }
  return value;
}

function booleanValue(value: unknown, label: string) {
  if (typeof value !== "boolean") throw new TypeError(`Invalid ${label}`);
  return value;
}

function decodeVersion(raw: unknown): FormalArtifactVersion {
  const value = record(raw);
  return {
    fileVersionId: stringValue(value.fileVersionId, "fileVersionId"),
    versionNumber: numberValue(value.versionNumber, "versionNumber"),
    objectPath: stringValue(value.objectPath, "objectPath"),
    originalName: stringValue(value.originalName, "originalName"),
    mimeType: stringValue(value.mimeType, "mimeType"),
    sizeBytes: numberValue(value.sizeBytes, "sizeBytes"),
    createdAt: stringValue(value.createdAt, "createdAt"),
  };
}

function decodeBinding(raw: unknown): ArtifactBindingState | null {
  if (raw === null || raw === undefined) return null;
  const value = record(raw);
  const strength = stringValue(value.strength, "strength");
  if (strength !== "light" && strength !== "strong") {
    throw new TypeError("Invalid binding strength");
  }
  return {
    bindingId: stringValue(value.bindingId, "bindingId"),
    fileVersionId: stringValue(value.fileVersionId, "fileVersionId"),
    boundVersionNumber: numberValue(
      value.boundVersionNumber,
      "boundVersionNumber",
    ),
    strength,
    version: numberValue(value.version, "binding version"),
  };
}

function decodeArtifact(raw: unknown): UpstreamArtifact {
  const value = record(raw);
  if (!Array.isArray(value.versions)) {
    throw new TypeError("Invalid artifact versions");
  }
  return {
    upstreamTaskId: stringValue(value.upstreamTaskId, "upstreamTaskId"),
    upstreamTaskTitle: stringValue(
      value.upstreamTaskTitle,
      "upstreamTaskTitle",
    ),
    fileId: stringValue(value.fileId, "fileId"),
    logicalName: stringValue(value.logicalName, "logicalName"),
    versions: value.versions.map(decodeVersion),
    latestVersionId: stringValue(value.latestVersionId, "latestVersionId"),
    binding: decodeBinding(value.binding),
  };
}

function decodeSnapshot(raw: unknown): UpstreamArtifactsSnapshot {
  const value = record(raw);
  if (!Array.isArray(value.artifacts)) {
    throw new TypeError("Invalid upstream artifacts");
  }
  return {
    downstreamTaskId: stringValue(value.downstreamTaskId, "downstreamTaskId"),
    canBind: booleanValue(value.canBind, "canBind"),
    artifacts: value.artifacts.map(decodeArtifact),
  };
}

function decodeCommand(raw: unknown): ArtifactBindingCommandResult {
  const value = record(raw);
  if (value.ok === false) {
    return {
      ok: false,
      code: stringValue(value.code, "command code"),
      ...(typeof value.field === "string" ? { field: value.field } : {}),
      ...(typeof value.currentVersion === "number"
        ? { currentVersion: value.currentVersion }
        : {}),
      ...(typeof value.requestId === "string"
        ? { requestId: value.requestId }
        : {}),
      ...(typeof value.replayed === "boolean"
        ? { replayed: value.replayed }
        : {}),
    };
  }
  if (value.ok !== true) throw new TypeError("Invalid command result");
  const data = record(value.data);
  const strength = stringValue(data.strength, "strength");
  if (strength !== "light" && strength !== "strong") {
    throw new TypeError("Invalid binding strength");
  }
  return {
    ok: true,
    data: {
      bindingId: stringValue(data.bindingId, "bindingId"),
      downstreamTaskId: stringValue(data.downstreamTaskId, "downstreamTaskId"),
      fileVersionId: stringValue(data.fileVersionId, "fileVersionId"),
      strength,
      bindingVersion: numberValue(data.bindingVersion, "bindingVersion"),
      changed: booleanValue(data.changed, "changed"),
    },
    ...(typeof value.requestId === "string"
      ? { requestId: value.requestId }
      : {}),
    ...(typeof value.replayed === "boolean"
      ? { replayed: value.replayed }
      : {}),
  };
}

function assertNoError(error: unknown) {
  if (error) throw error;
}

export function createArtifactBindingRepository(
  client: SupabaseClient<Database>,
) {
  async function listUpstreamArtifacts(
    downstreamTaskId: string,
  ): Promise<UpstreamArtifactsSnapshot> {
    const { data, error } = await client.rpc("get_upstream_artifacts", {
      p_downstream_task_id: downstreamTaskId,
    });
    assertNoError(error);
    return decodeSnapshot(data);
  }

  async function recordArtifactUse(input: {
    projectId: string;
    downstreamTaskId: string;
    fileVersionId: string;
    requestId: string;
  }) {
    const { data, error } = await client.rpc("cmd_record_task_artifact_use", {
      p_project_id: input.projectId,
      p_downstream_task_id: input.downstreamTaskId,
      p_file_version_id: input.fileVersionId,
      p_request_id: input.requestId,
    });
    assertNoError(error);
    return decodeCommand(data);
  }

  async function setBindingStrength(input: {
    projectId: string;
    downstreamTaskId: string;
    fileVersionId: string;
    strength: ArtifactBindingStrength;
    requestId: string;
    expectedVersion: number;
  }) {
    const { data, error } = await client.rpc(
      "cmd_set_task_artifact_binding_strength",
      {
        p_project_id: input.projectId,
        p_downstream_task_id: input.downstreamTaskId,
        p_file_version_id: input.fileVersionId,
        p_strength: input.strength,
        p_request_id: input.requestId,
        p_expected_version: input.expectedVersion,
      },
    );
    assertNoError(error);
    return decodeCommand(data);
  }

  async function switchBindingVersion(input: {
    projectId: string;
    downstreamTaskId: string;
    fileVersionId: string;
    requestId: string;
    expectedVersion: number;
  }) {
    const { data, error } = await client.rpc(
      "cmd_switch_task_artifact_binding_version",
      {
        p_project_id: input.projectId,
        p_downstream_task_id: input.downstreamTaskId,
        p_file_version_id: input.fileVersionId,
        p_request_id: input.requestId,
        p_expected_version: input.expectedVersion,
      },
    );
    assertNoError(error);
    return decodeCommand(data);
  }

  async function createSignedFileUrl(objectPath: string) {
    const { data, error } = await client.storage
      .from("teamup-files")
      .createSignedUrl(objectPath, 600);
    assertNoError(error);
    return data!.signedUrl;
  }

  return {
    listUpstreamArtifacts,
    recordArtifactUse,
    setBindingStrength,
    switchBindingVersion,
    createSignedFileUrl,
  };
}
