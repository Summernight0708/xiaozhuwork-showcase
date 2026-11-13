import { describe, expect, it, vi } from "vitest";
import { uploadTaskFile } from "@/services/file-upload";

function opts(finalizeResponse: unknown) {
  return {
    projectId: "a8200000-0000-0000-0000-000000000002",
    taskId: "a8300000-0000-0000-0000-000000000002",
    expectedVersion: 1,
    file: new File(["pdf"], "f.pdf", { type: "application/pdf" }),
    mode: "new_file" as const,
    reserve: vi.fn().mockResolvedValue({
      ok: true,
      data: {
        reservationId: "a8400000-0000-0000-0000-000000000001",
        objectPath:
          "pending/a8200000-0000-0000-0000-000000000002/a8400000-0000-0000-0000-000000000001/f.pdf",
        expiresAt: "2099-01-01T00:00:00Z",
      },
      requestId: "reserve-1",
      replayed: false,
      aggregateVersion: 1,
    }),
    storageUpload: vi
      .fn()
      .mockResolvedValue({ data: { path: "f.pdf" }, error: null }),
    finalize: vi
      .fn()
      .mockResolvedValue({ data: finalizeResponse, error: null }),
    requestIdFactory: vi
      .fn()
      .mockReturnValueOnce("reserve-1")
      .mockReturnValueOnce("finalize-1"),
  };
}

describe("Pro Phase 2 storage upload response compatibility", () => {
  it("preserves scope and exact binary capacity when finalize returns a project-quota denial", async () => {
    const api = opts({
      ok: false,
      code: "STORAGE_QUOTA_EXCEEDED",
      details: { scope: "project", limitBytes: 536870912 },
      requestId: "finalize-1",
      replayed: false,
    });
    const result = await uploadTaskFile(api);
    expect(result).toEqual(
      expect.objectContaining({
        ok: false,
        code: "STORAGE_QUOTA_EXCEEDED",
        details: { scope: "project", limitBytes: 536870912 },
      }),
    );
    expect(api.storageUpload).toHaveBeenCalledWith(
      expect.stringContaining("/f.pdf"),
      api.file,
      expect.objectContaining({ upsert: false }),
    );
  });
  it("ignores untrusted quota details without throwing or widening accepted scopes", async () => {
    const result = await uploadTaskFile(
      opts({
        ok: false,
        code: "FILE_VALIDATION_FAILED",
        details: { scope: "another-project", limitBytes: "untrusted" },
      }),
    );
    expect(result).toMatchObject({
      ok: false,
      code: "FILE_VALIDATION_FAILED",
      details: {},
    });
  });
});
