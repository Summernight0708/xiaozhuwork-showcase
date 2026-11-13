import { expect, test, vi } from "vitest";
import { prepareEvidenceAttempt } from "@/features/external-evidence/attempt";
import type { ExternalEvidenceRepository } from "@/features/external-evidence/types";

test("transport retry keeps the original ID, draft and version; stale failures require a new user action", async () => {
  const stale = {
    ok: false,
    code: "STALE_VERSION",
    requestId: "request",
    replayed: false,
    currentVersion: 3,
  };
  const create = vi
    .fn()
    .mockRejectedValueOnce(new Error("Connection lost"))
    .mockResolvedValue(stale);
  const repo = { create } as unknown as ExternalEvidenceRepository;
  const input = {
    projectId: "p",
    taskId: "t",
    httpsUrl: "https://github.com/a",
    description: "Original",
    expectedVersion: 1,
  };
  const attempt = prepareEvidenceAttempt(
    repo,
    { kind: "create", input },
    "request",
  );
  await expect(attempt.execute()).rejects.toThrow("Connection lost");
  input.description = "Draft changed after timeout";
  input.expectedVersion = 2;
  const retry = attempt.execute();
  expect(attempt.execute()).toBe(retry);
  expect(await retry).toEqual(stale);
  expect(create).toHaveBeenCalledTimes(2);
  expect(create.mock.calls[0]).toEqual(create.mock.calls[1]);
  expect(create.mock.calls[1]![0]).toMatchObject({
    requestId: "request",
    description: "Original",
    expectedVersion: 1,
  });
  await attempt.execute();
  expect(create).toHaveBeenCalledTimes(2);
});
