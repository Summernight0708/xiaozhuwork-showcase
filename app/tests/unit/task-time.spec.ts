import { describe, expect, it } from "vitest";

import {
  calculatePenaltyRatio,
  freeAbandonmentDeadline,
  resolveEffectiveStart,
  validateFutureDeadline,
} from "../../src/domain/task-time";

describe("task time baselines", () => {
  it("waits for all upstreams and starts at the latest completion time", () => {
    expect(
      resolveEffectiveStart({
        acceptedAt: "2026-09-20T09:00:00Z",
        upstreamCompletedAt: ["2026-09-21T10:00:00Z", null],
      }),
    ).toBeNull();

    expect(
      resolveEffectiveStart({
        acceptedAt: "2026-09-20T09:00:00Z",
        upstreamCompletedAt: ["2026-09-21T10:00:00Z", "2026-09-22T11:00:00Z"],
      }),
    ).toBe("2026-09-22T11:00:00.000Z");
  });

  it("uses acceptance as the start when there are no upstream tasks", () => {
    expect(
      resolveEffectiveStart({
        acceptedAt: "2026-09-20T09:00:00Z",
        upstreamCompletedAt: [],
      }),
    ).toBe("2026-09-20T09:00:00.000Z");
  });

  it("requires a deadline strictly after the effective start", () => {
    expect(
      validateFutureDeadline("2026-09-20T09:00:00Z", "2026-09-20T09:00:00Z"),
    ).toEqual({ valid: false, code: "DDL_NOT_IN_FUTURE" });
    expect(
      validateFutureDeadline("2026-09-20T09:00:00Z", "2026-09-20T09:00:01Z"),
    ).toEqual({ valid: true });
  });

  it("calculates the free abandonment window from the effective baseline", () => {
    expect(
      freeAbandonmentDeadline("2026-09-20T09:00:00Z", "2026-09-20T10:00:00Z"),
    ).toBe("2026-09-20T09:06:00.000Z");
  });

  it("rejects penalty ratios when the captured duration is nonpositive", () => {
    expect(
      calculatePenaltyRatio({
        startAt: "2026-09-20T10:00:00Z",
        deadlineAt: "2026-09-20T10:00:00Z",
        eventAt: "2026-09-20T10:01:00Z",
        kind: "late_submission",
      }),
    ).toEqual({ valid: false, code: "DDL_NOT_IN_FUTURE" });
  });

  it("uses the captured start and deadline for late submission ratio", () => {
    expect(
      calculatePenaltyRatio({
        startAt: "2026-09-20T09:00:00Z",
        deadlineAt: "2026-09-20T10:00:00Z",
        eventAt: "2026-09-20T10:30:00Z",
        kind: "late_submission",
      }),
    ).toEqual({ valid: true, ratio: 0.5 });
  });

  it("uses the captured free-window end for late abandonment ratio", () => {
    expect(
      calculatePenaltyRatio({
        startAt: "2026-09-20T09:00:00Z",
        deadlineAt: "2026-09-20T10:00:00Z",
        eventAt: "2026-09-20T09:36:00Z",
        kind: "late_abandonment",
      }),
    ).toEqual({ valid: true, ratio: 0.5 });
  });
});
