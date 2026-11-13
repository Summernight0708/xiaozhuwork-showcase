import { describe, expect, it, vi } from "vitest";
import {
  freeAbandonUntilMs,
  lateFirstSubmission,
} from "../../src/features/task-disposition/timing";
import { quarantineWithdrawnVersion } from "../../src/features/file-withdrawal/quarantine";

describe("C responsibility windows", () => {
  it("uses integer seconds and exactly ten percent without min/max clamp", () => {
    expect(freeAbandonUntilMs(0, 120_000)).toBe(12_000);
    expect(freeAbandonUntilMs(0, 19_900)).toBe(1_000);
    expect(freeAbandonUntilMs(0, 900)).toBeNull();
    expect(freeAbandonUntilMs(10_000, 10_000)).toBeNull();
  });
  it("does not treat review approval or blocked submission as first late", () => {
    expect(lateFirstSubmission(5000, 4000, false)).toBe(true);
    expect(lateFirstSubmission(5000, 4000, true)).toBe(false);
    expect(lateFirstSubmission(null, 4000, false)).toBe(false);
  });
});

describe("C storage quarantine worker", () => {
  const intent = {
    withdrawalId: "w1",
    state: "pending_quarantine" as const,
    bucket: "teamup-files" as const,
    originalPath: "final/a",
    quarantinePath: "quarantine/withdrawal/q1",
  };
  it("moves object before completing authoritative SQL state", async () => {
    let original = true;
    let quarantine = false;
    const complete = vi.fn(async () => ({ ok: true, state: "withdrawn" }));
    const move = vi.fn(async () => {
      original = false;
      quarantine = true;
    });
    const result = await quarantineWithdrawnVersion(intent, {
      exists: async (_b, path) =>
        path === intent.originalPath ? original : quarantine,
      move,
      complete,
    });
    expect(result).toBe("quarantined");
    expect(move).toHaveBeenCalledOnce();
    expect(complete).toHaveBeenCalledWith("w1");
  });
  it("retries idempotently after a successful move but failed DB completion", async () => {
    const move = vi.fn();
    const complete = vi.fn(async () => ({ ok: true, state: "withdrawn" }));
    expect(
      await quarantineWithdrawnVersion(intent, {
        exists: async (_b, path) => path === intent.quarantinePath,
        move,
        complete,
      }),
    ).toBe("quarantined");
    expect(move).not.toHaveBeenCalled();
  });
  it("fails closed when source and quarantine both exist", async () => {
    const complete = vi.fn();
    await expect(
      quarantineWithdrawnVersion(intent, {
        exists: async () => true,
        move: vi.fn(),
        complete,
      }),
    ).rejects.toThrow("Both storage locations");
    expect(complete).not.toHaveBeenCalled();
  });
});
