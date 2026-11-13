import { describe, expect, it } from "vitest";
import {
  FOLLOWUP_EVENT_TYPES,
  TASK_SHARE_TOTAL_BPS,
  hasExactTaskSharePool,
  mayAutoAssessFollowupPenalty,
} from "@/domain/followup-contracts";

describe("F0 shared invariants (not feature implementation)", () => {
  it("freezes unique event names", () => {
    expect(new Set(FOLLOWUP_EVENT_TYPES).size).toBe(
      FOLLOWUP_EVENT_TYPES.length,
    );
    expect(FOLLOWUP_EVENT_TYPES).toContain("task_canceled");
    expect(FOLLOWUP_EVENT_TYPES).toContain("task_responsibility_abandoned");
    expect(FOLLOWUP_EVENT_TYPES).toContain("task_first_submitted_late");
  });
  it("enforces exactly one unduplicated task pool", () => {
    expect(TASK_SHARE_TOTAL_BPS).toBe(10000);
    expect(
      hasExactTaskSharePool([
        { memberId: "a", shareBps: 6500 },
        { memberId: "b", shareBps: 3500 },
      ]),
    ).toBe(true);
    expect(hasExactTaskSharePool([{ memberId: "a", shareBps: 10000 }])).toBe(
      true,
    );
    expect(
      hasExactTaskSharePool([
        { memberId: "a", shareBps: 10000 },
        { memberId: "b", shareBps: 10000 },
      ]),
    ).toBe(false);
    expect(
      hasExactTaskSharePool([
        { memberId: "a", shareBps: 5000 },
        { memberId: "a", shareBps: 5000 },
      ]),
    ).toBe(false);
    expect(hasExactTaskSharePool([{ memberId: "a", shareBps: 9999.9 }])).toBe(
      false,
    );
    expect(
      hasExactTaskSharePool([
        { memberId: "a", shareBps: 0 },
        { memberId: "b", shareBps: 10000 },
      ]),
    ).toBe(false);
    expect(hasExactTaskSharePool([])).toBe(false);
  });
  it("excludes cancellation, no consent, facts_only, and blocks", () => {
    const base = {
      contributionMode: "weighted" as const,
      autoPenaltyEnabled: true,
      blockedExempt: false,
    };
    expect(
      mayAutoAssessFollowupPenalty({ ...base, cause: "task_canceled" }),
    ).toBe(false);
    expect(
      mayAutoAssessFollowupPenalty({
        ...base,
        cause: "task_responsibility_abandoned",
      }),
    ).toBe(true);
    expect(
      mayAutoAssessFollowupPenalty({
        ...base,
        cause: "task_first_submitted_late",
      }),
    ).toBe(true);
    expect(
      mayAutoAssessFollowupPenalty({
        ...base,
        cause: "task_first_submitted_late",
        autoPenaltyEnabled: false,
      }),
    ).toBe(false);
    expect(
      mayAutoAssessFollowupPenalty({
        ...base,
        cause: "task_first_submitted_late",
        contributionMode: "facts_only",
      }),
    ).toBe(false);
    expect(
      mayAutoAssessFollowupPenalty({
        ...base,
        cause: "task_first_submitted_late",
        blockedExempt: true,
      }),
    ).toBe(false);
  });
});
