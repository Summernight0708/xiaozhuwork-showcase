import { describe, expect, it, vi } from "vitest";

import { CommandTransportError } from "@/lib/command-adapter";
import { storageUploadErrorCode, uploadTaskFile } from "@/services/file-upload";

describe("task file upload pipeline", () => {
  it("reserves, uploads without upsert, then finalizes with a stable request id", async () => {
    const reserve = vi.fn().mockResolvedValue({
      ok: true,
      data: {
        reservationId: "11111111-1111-4111-8111-111111111111",
        objectPath: "pending/p/r/file.pdf",
        expiresAt: "2026-09-30T00:00:00Z",
      },
      requestId: "22222222-2222-4222-8222-222222222222",
      replayed: false,
      aggregateType: "file_upload_reservation",
      aggregateId: "11111111-1111-4111-8111-111111111111",
      aggregateVersion: 1,
    });
    const upload = vi.fn().mockResolvedValue({
      data: { path: "pending/p/r/file.pdf" },
      error: null,
    });
    const finalize = vi.fn().mockResolvedValue({
      data: {
        ok: true,
        data: {
          fileId: "file-1",
          fileVersionId: "version-1",
          versionNumber: 1,
        },
        requestId: "33333333-3333-4333-8333-333333333333",
        replayed: false,
        aggregateType: "file_upload_reservation",
        aggregateId: "11111111-1111-4111-8111-111111111111",
        aggregateVersion: 2,
      },
      error: null,
    });

    const file = new File(["hello"], "file.pdf", { type: "application/pdf" });
    const result = await uploadTaskFile({
      projectId: "project-1",
      taskId: "task-1",
      expectedVersion: 4,
      file,
      mode: "new_file",
      reserve,
      storageUpload: upload,
      finalize,
      requestIdFactory: vi
        .fn()
        .mockReturnValueOnce("22222222-2222-4222-8222-222222222222")
        .mockReturnValueOnce("33333333-3333-4333-8333-333333333333"),
    });

    expect(result.ok).toBe(true);
    expect(reserve).toHaveBeenCalledWith(
      expect.objectContaining({ expectedVersion: 4, mode: "new_file" }),
    );
    expect(upload).toHaveBeenCalledWith("pending/p/r/file.pdf", file, {
      cacheControl: "3600",
      contentType: "application/pdf",
      upsert: false,
    });
    expect(finalize).toHaveBeenCalledWith({
      reservationId: "11111111-1111-4111-8111-111111111111",
      requestId: "33333333-3333-4333-8333-333333333333",
      expectedVersion: 1,
    });
  });

  it("retries reserve transport failures with the same request id", async () => {
    const reserve = vi
      .fn()
      .mockRejectedValueOnce(new CommandTransportError("reserve-request", true))
      .mockResolvedValueOnce({
        ok: true,
        data: {
          reservationId: "reservation-1",
          objectPath: "pending/p/r/file.pdf",
          expiresAt: "2026-09-30T00:00:00Z",
        },
        requestId: "reserve-request",
        replayed: true,
        aggregateType: "file_upload_reservation",
        aggregateId: "reservation-1",
        aggregateVersion: 1,
      });
    const upload = vi.fn().mockResolvedValue({ data: {}, error: null });
    const finalize = vi.fn().mockResolvedValue({
      data: {
        ok: true,
        data: {
          fileId: "file-1",
          fileVersionId: "version-1",
          versionNumber: 1,
        },
        requestId: "finalize-request",
        replayed: false,
      },
      error: null,
    });

    const result = await uploadTaskFile({
      projectId: "project-1",
      taskId: "task-1",
      expectedVersion: 4,
      file: new File(["hello"], "file.pdf", { type: "application/pdf" }),
      mode: "new_file",
      reserve,
      storageUpload: upload,
      finalize,
      requestIdFactory: vi
        .fn()
        .mockReturnValueOnce("reserve-request")
        .mockReturnValueOnce("finalize-request"),
    });

    expect(result.ok).toBe(true);
    expect(reserve).toHaveBeenCalledTimes(2);
    expect(reserve.mock.calls[0]?.[0].requestId).toBe("reserve-request");
    expect(reserve.mock.calls[1]?.[0].requestId).toBe("reserve-request");
  });

  it("retries ambiguous finalize transport failures with the same request id without re-uploading", async () => {
    const reserve = vi.fn().mockResolvedValue({
      ok: true,
      data: {
        reservationId: "reservation-1",
        objectPath: "pending/p/r/file.pdf",
        expiresAt: "2026-09-30T00:00:00Z",
      },
      requestId: "reserve-request",
      replayed: false,
      aggregateType: "file_upload_reservation",
      aggregateId: "reservation-1",
      aggregateVersion: 1,
    });
    const upload = vi.fn().mockResolvedValue({ data: {}, error: null });
    const transportError = Object.assign(new Error("network"), {
      name: "FunctionsFetchError",
    });
    const finalize = vi
      .fn()
      .mockResolvedValueOnce({ data: null, error: transportError })
      .mockResolvedValueOnce({
        data: {
          ok: true,
          data: {
            fileId: "file-1",
            fileVersionId: "version-1",
            versionNumber: 1,
          },
          requestId: "finalize-request",
          replayed: true,
        },
        error: null,
      });

    const result = await uploadTaskFile({
      projectId: "project-1",
      taskId: "task-1",
      expectedVersion: 4,
      file: new File(["hello"], "file.pdf", { type: "application/pdf" }),
      mode: "new_file",
      reserve,
      storageUpload: upload,
      finalize,
      requestIdFactory: vi
        .fn()
        .mockReturnValueOnce("reserve-request")
        .mockReturnValueOnce("finalize-request"),
    });

    expect(result.ok).toBe(true);
    expect(finalize).toHaveBeenCalledTimes(2);
    expect(finalize.mock.calls[0]?.[0].requestId).toBe("finalize-request");
    expect(finalize.mock.calls[1]?.[0].requestId).toBe("finalize-request");
    expect(upload).toHaveBeenCalledTimes(1);
  });
});

describe("Storage MIME refusal messaging", () => {
  it("reports a declared MIME that the private bucket rejects", () => {
    expect(storageUploadErrorCode({ statusCode: "415" })).toBe(
      "FILE_TYPE_NOT_ALLOWED",
    );
    expect(storageUploadErrorCode({ code: "invalid_mime_type" })).toBe(
      "FILE_TYPE_NOT_ALLOWED",
    );
  });
  it("reports Storage authentication and RLS failures rather than incomplete uploads", () => {
    expect(storageUploadErrorCode({ statusCode: "401" })).toBe(
      "UNAUTHENTICATED",
    );
    expect(storageUploadErrorCode({ status: 403 })).toBe("NOT_AUTHORIZED");
    expect(storageUploadErrorCode({ statusCode: "403" })).toBe(
      "NOT_AUTHORIZED",
    );
  });
  it("preserves transient storage failures for retry", () => {
    expect(storageUploadErrorCode({ statusCode: "503" })).toBe(
      "UPLOAD_NOT_READY",
    );
    expect(storageUploadErrorCode({ message: "network failed" })).toBe(
      "UPLOAD_NOT_READY",
    );
    expect(storageUploadErrorCode(null)).toBe("UPLOAD_NOT_READY");
  });
});

describe("MP4 bucket restriction failure propagation", () => {
  it("does not finalize when Storage returns an explicit MIME refusal", async () => {
    const reserve = vi.fn().mockResolvedValue({
      ok: true,
      data: {
        reservationId: "reservation-mp4",
        objectPath: "pending/test/mobile.mp4",
        expiresAt: "2026-10-08T20:00:00Z",
      },
      aggregateVersion: 1,
    });
    const storageUpload = vi.fn().mockResolvedValue({
      data: null,
      error: { statusCode: "415", code: "invalid_mime_type" },
    });
    const finalize = vi.fn();
    const result = await uploadTaskFile({
      projectId: "project",
      taskId: "task",
      expectedVersion: 1,
      file: new File(["mp4"], "phone.mp4", { type: "video/mp4" }),
      mode: "new_file",
      reserve,
      storageUpload,
      finalize,
      requestIdFactory: () => "request-test",
    });
    expect(result).toMatchObject({ ok: false, code: "FILE_TYPE_NOT_ALLOWED" });
    expect(storageUpload).toHaveBeenCalledWith(
      "pending/test/mobile.mp4",
      expect.any(File),
      expect.objectContaining({ contentType: "video/mp4", upsert: false }),
    );
    expect(finalize).not.toHaveBeenCalled();
  });
});
