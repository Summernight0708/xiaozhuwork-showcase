import { describe, expect, it, vi } from "vitest";

import { CommandTransportError } from "@/lib/command-adapter";
import { runIdempotentCommand } from "@/services/command-runner";

describe("runIdempotentCommand", () => {
  it("reuses the same request id for a retryable transport retry", async () => {
    const execute = vi
      .fn()
      .mockRejectedValueOnce(new CommandTransportError("request-1", true))
      .mockResolvedValueOnce({
        ok: true,
        data: { taskId: "task-1" },
        requestId: "request-1",
        replayed: true,
        aggregateType: "task",
        aggregateId: "task-1",
        aggregateVersion: 2,
      });

    const result = await runIdempotentCommand({
      requestId: "request-1",
      execute,
      maxTransportRetries: 1,
    });

    expect(result.ok).toBe(true);
    expect(execute).toHaveBeenCalledTimes(2);
    expect(execute).toHaveBeenNthCalledWith(1, "request-1");
    expect(execute).toHaveBeenNthCalledWith(2, "request-1");
  });

  it("refreshes on stale version and returns the domain failure without silent overwrite", async () => {
    const refresh = vi.fn().mockResolvedValue(undefined);
    const execute = vi.fn().mockResolvedValue({
      ok: false,
      code: "STALE_VERSION",
      requestId: "request-2",
      replayed: false,
      currentVersion: 7,
    });

    const result = await runIdempotentCommand({
      requestId: "request-2",
      execute,
      onStaleVersion: refresh,
    });

    expect(result).toMatchObject({
      ok: false,
      code: "STALE_VERSION",
      currentVersion: 7,
    });
    expect(refresh).toHaveBeenCalledWith(7);
    expect(execute).toHaveBeenCalledTimes(1);
  });

  it("returns stable domain failures without retrying or swallowing them", async () => {
    const execute = vi.fn().mockResolvedValue({
      ok: false,
      code: "IDEMPOTENCY_KEY_REUSED",
      requestId: "request-3",
      replayed: false,
    });

    const result = await runIdempotentCommand({
      requestId: "request-3",
      execute,
      maxTransportRetries: 1,
    });

    expect(result).toMatchObject({
      ok: false,
      code: "IDEMPOTENCY_KEY_REUSED",
      requestId: "request-3",
    });
    expect(execute).toHaveBeenCalledTimes(1);
  });
});
