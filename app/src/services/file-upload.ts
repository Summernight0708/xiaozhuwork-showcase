import { CommandTransportError } from "@/lib/command-adapter";

import type {
  CommandResult,
  ReserveTaskFileUploadData,
} from "@/types/commands";

export type FinalizeUploadSuccess = {
  fileId: string;
  fileVersionId: string;
  versionNumber: number;
};

export type FinalizeUploadResult =
  | {
      ok: true;
      data: FinalizeUploadSuccess;
      requestId?: string;
      replayed?: boolean;
    }
  | {
      ok: false;
      code: string;
      requestId?: string | null;
      replayed?: boolean;
      field?: string;
      details?: { scope?: "file" | "project"; limitBytes?: number };
      currentVersion?: number;
    };

export interface UploadTaskFileOptions {
  projectId: string;
  taskId: string;
  expectedVersion: number;
  file: File;
  mode: "new_file" | "new_version";
  targetFileId?: string;
  reserve: (input: {
    projectId: string;
    taskId: string;
    requestId: string;
    expectedVersion: number;
    mode: "new_file" | "new_version";
    targetFileId?: string;
    originalName: string;
    declaredMimeType: string;
    declaredSizeBytes: number;
  }) => Promise<CommandResult<ReserveTaskFileUploadData>>;
  storageUpload: (
    objectPath: string,
    file: File,
    options: {
      cacheControl: string;
      contentType: string;
      upsert: false;
    },
  ) => Promise<{ data: unknown; error: unknown }>;
  finalize: (body: {
    reservationId: string;
    requestId: string;
    expectedVersion: number;
  }) => Promise<{ data: unknown; error: unknown }>;
  requestIdFactory: () => string;
}

function decodeFinalizeResult(value: unknown): FinalizeUploadResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, code: "SERVICE_UNAVAILABLE" };
  }
  const record = value as Record<string, unknown>;
  if (record.ok === false && typeof record.code === "string") {
    return {
      ok: false,
      code: record.code,
      requestId: typeof record.requestId === "string" ? record.requestId : null,
      replayed: record.replayed === true,
      field: typeof record.field === "string" ? record.field : undefined,
      details:
        record.details &&
        typeof record.details === "object" &&
        !Array.isArray(record.details)
          ? (() => {
              const details = record.details as Record<string, unknown>;
              return {
                ...(details.scope === "file" || details.scope === "project"
                  ? { scope: details.scope }
                  : {}),
                ...(typeof details.limitBytes === "number" &&
                Number.isSafeInteger(details.limitBytes)
                  ? { limitBytes: details.limitBytes }
                  : {}),
              };
            })()
          : undefined,
      currentVersion:
        typeof record.currentVersion === "number"
          ? record.currentVersion
          : undefined,
    };
  }
  if (
    record.ok === true &&
    record.data &&
    typeof record.data === "object" &&
    !Array.isArray(record.data)
  ) {
    const data = record.data as Record<string, unknown>;
    if (
      typeof data.fileId === "string" &&
      typeof data.fileVersionId === "string" &&
      typeof data.versionNumber === "number"
    ) {
      return {
        ok: true,
        data: {
          fileId: data.fileId,
          fileVersionId: data.fileVersionId,
          versionNumber: data.versionNumber,
        },
        requestId:
          typeof record.requestId === "string" ? record.requestId : undefined,
        replayed: record.replayed === true,
      };
    }
  }
  return { ok: false, code: "SERVICE_UNAVAILABLE" };
}

/** Keep Storage RLS refusals distinct from incomplete or transient uploads. */
export function storageUploadErrorCode(
  error: unknown,
):
  | "FILE_TYPE_NOT_ALLOWED"
  | "UNAUTHENTICATED"
  | "NOT_AUTHORIZED"
  | "UPLOAD_NOT_READY" {
  if (!error || typeof error !== "object") return "UPLOAD_NOT_READY";
  const record = error as {
    status?: unknown;
    statusCode?: unknown;
    code?: unknown;
  };
  const status = record.statusCode ?? record.status;
  const code = typeof record.code === "string" ? record.code.toLowerCase() : "";
  if (status === 415 || status === "415" || code === "invalid_mime_type") {
    return "FILE_TYPE_NOT_ALLOWED";
  }
  if (status === 401 || status === "401") return "UNAUTHENTICATED";
  if (status === 403 || status === "403") return "NOT_AUTHORIZED";
  return "UPLOAD_NOT_READY";
}

function isRetryableFunctionTransportError(error: unknown) {
  if (!error || typeof error !== "object") return false;
  const name = (error as { name?: unknown }).name;
  return name === "FunctionsFetchError" || name === "FunctionsRelayError";
}

async function reserveWithStableRetry(
  options: UploadTaskFileOptions,
  input: Parameters<UploadTaskFileOptions["reserve"]>[0],
) {
  try {
    return await options.reserve(input);
  } catch (error) {
    if (!(error instanceof CommandTransportError) || !error.retryable)
      throw error;
    return options.reserve(input);
  }
}

async function finalizeWithStableRetry(
  options: UploadTaskFileOptions,
  body: Parameters<UploadTaskFileOptions["finalize"]>[0],
) {
  let response: Awaited<ReturnType<UploadTaskFileOptions["finalize"]>>;
  try {
    response = await options.finalize(body);
  } catch (error) {
    if (!isRetryableFunctionTransportError(error)) throw error;
    return options.finalize(body);
  }
  if (response.error && isRetryableFunctionTransportError(response.error)) {
    return options.finalize(body);
  }
  return response;
}

export async function uploadTaskFile(
  options: UploadTaskFileOptions,
): Promise<FinalizeUploadResult> {
  const reserveRequestId = options.requestIdFactory();
  const reserveInput = {
    projectId: options.projectId,
    taskId: options.taskId,
    requestId: reserveRequestId,
    expectedVersion: options.expectedVersion,
    mode: options.mode,
    ...(options.targetFileId ? { targetFileId: options.targetFileId } : {}),
    originalName: options.file.name,
    declaredMimeType: options.file.type || "application/octet-stream",
    declaredSizeBytes: options.file.size,
  } as const;
  const reservation = await reserveWithStableRetry(options, reserveInput);
  if (!reservation.ok) return reservation;

  const uploaded = await options.storageUpload(
    reservation.data.objectPath,
    options.file,
    {
      cacheControl: "3600",
      contentType: options.file.type || "application/octet-stream",
      upsert: false,
    },
  );
  if (uploaded.error) {
    return {
      ok: false,
      code: storageUploadErrorCode(uploaded.error),
      requestId: reserveRequestId,
      replayed: false,
    };
  }

  const finalizeRequestId = options.requestIdFactory();
  const finalizeBody = {
    reservationId: reservation.data.reservationId,
    requestId: finalizeRequestId,
    expectedVersion: reservation.aggregateVersion,
  };
  const finalized = await finalizeWithStableRetry(options, finalizeBody);
  if (finalized.error) {
    return {
      ok: false,
      code: "SERVICE_UNAVAILABLE",
      requestId: finalizeRequestId,
      replayed: false,
    };
  }
  return decodeFinalizeResult(finalized.data);
}
