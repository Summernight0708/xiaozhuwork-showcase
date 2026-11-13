import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, test, vi } from "vitest";
import type { Database } from "@/types/database.generated";
import {
  createExternalEvidenceRepository,
  decodeEvidenceCommand,
} from "@/features/external-evidence/repository";

const success = {
  ok: true,
  requestId: "request-1",
  replayed: false,
  aggregateType: "task",
  aggregateId: "task-1",
  aggregateVersion: 2,
  data: {
    evidenceId: "evidence-1",
    taskId: "task-1",
    taskVersion: 2,
    evidenceVersion: 1,
    revokedAt: null,
  },
};
describe("external evidence repository", () => {
  test("scopes both paginated reads to project and entity and propagates read failures", async () => {
    const query = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      order: vi.fn().mockReturnThis(),
      range: vi.fn().mockResolvedValue({ data: [], error: null }),
    };
    const from = vi.fn().mockReturnValue(query);
    const repo = createExternalEvidenceRepository({
      from,
    } as unknown as SupabaseClient<Database>);
    expect(await repo.list("p", "t", { offset: 200, limit: 50 })).toEqual([]);
    expect(from).toHaveBeenLastCalledWith("task_external_evidence");
    expect(query.eq.mock.calls).toEqual([
      ["project_id", "p"],
      ["task_id", "t"],
    ]);
    expect(query.range).toHaveBeenLastCalledWith(200, 249);
    query.eq.mockClear();
    await repo.revisions("p", "e");
    expect(from).toHaveBeenLastCalledWith("task_external_evidence_revisions");
    expect(query.eq.mock.calls).toEqual([
      ["project_id", "p"],
      ["evidence_id", "e"],
    ]);
    expect(query.range).toHaveBeenLastCalledWith(0, 99);
    await expect(repo.list("p", "t", { offset: -1 })).rejects.toThrow(
      RangeError,
    );
    await expect(
      repo.revisions("p", "e", { offset: 0, limit: 201 }),
    ).rejects.toThrow(RangeError);
    query.range.mockResolvedValueOnce({
      data: null,
      error: new Error("read denied"),
    });
    await expect(repo.list("p", "t")).rejects.toThrow("read denied");
  });
  test("maps all three F0 signatures and preserves caller request IDs on retry", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: success, error: null });
    const repo = createExternalEvidenceRepository({
      rpc,
    } as unknown as SupabaseClient<Database>);
    const input = {
      projectId: "project-1",
      taskId: "task-1",
      httpsUrl: "https://github.com/a/b",
      description: "source",
      requestId: "request-1",
      expectedVersion: 1,
    };
    await repo.create(input);
    await repo.create(input);
    expect(rpc.mock.calls[0]).toEqual(rpc.mock.calls[1]);
    expect(rpc).toHaveBeenNthCalledWith(1, "cmd_create_external_evidence", {
      p_project_id: "project-1",
      p_task_id: "task-1",
      p_https_url: input.httpsUrl,
      p_description: "source",
      p_request_id: "request-1",
      p_expected_version: 1,
    });
    await repo.update({ ...input, evidenceId: "evidence-1" });
    expect(rpc.mock.calls[2]![0]).toBe("cmd_update_external_evidence");
    expect(rpc.mock.calls[2]![1]).toEqual({
      p_project_id: "project-1",
      p_evidence_id: "evidence-1",
      p_https_url: input.httpsUrl,
      p_description: "source",
      p_request_id: "request-1",
      p_expected_version: 1,
    });
    await repo.remove({
      projectId: "project-1",
      evidenceId: "evidence-1",
      requestId: "remove-1",
      expectedVersion: 3,
    });
    expect(rpc).toHaveBeenLastCalledWith("cmd_remove_external_evidence", {
      p_project_id: "project-1",
      p_evidence_id: "evidence-1",
      p_request_id: "remove-1",
      p_expected_version: 3,
    });
  });
  test("surfaces transport errors without retrying and preserves stale failures", async () => {
    const rpc = vi
      .fn()
      .mockResolvedValue({ data: null, error: new Error("offline") });
    const repo = createExternalEvidenceRepository({
      rpc,
    } as unknown as SupabaseClient<Database>);
    await expect(
      repo.remove({
        projectId: "p",
        evidenceId: "e",
        requestId: "r",
        expectedVersion: 1,
      }),
    ).rejects.toThrow("offline");
    expect(rpc).toHaveBeenCalledTimes(1);
    const failure = {
      ok: false,
      code: "STALE_VERSION",
      currentVersion: 3,
      requestId: "r",
      replayed: false,
    };
    expect(decodeEvidenceCommand(failure)).toEqual(failure);
    expect(() =>
      decodeEvidenceCommand({ ...success, aggregateVersion: "2" }),
    ).toThrow();
  });
});
