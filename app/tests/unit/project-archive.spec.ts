import { describe, expect, it } from "vitest";

import { archiveRetentionPhase } from "@/features/project-archive/repository";

describe("archiveRetentionPhase", () => {
  const cycle = {
    retain_until: "2027-10-10T00:00:00.000Z",
    recovery_until: "2027-11-09T00:00:00.000Z",
  };

  it("allows retention extension before the retention deadline", () => {
    expect(
      archiveRetentionPhase(cycle, Date.parse("2027-10-09T23:59:59Z")),
    ).toBe("retained");
  });

  it("allows recovery but not extension for the 30-day recovery-only window", () => {
    expect(archiveRetentionPhase(cycle, Date.parse(cycle.retain_until))).toBe(
      "recovery_only",
    );
    expect(archiveRetentionPhase(cycle, Date.parse(cycle.recovery_until))).toBe(
      "recovery_only",
    );
  });

  it("rejects restoration after the recovery window", () => {
    expect(
      archiveRetentionPhase(cycle, Date.parse("2027-11-09T00:00:01Z")),
    ).toBe("expired");
    expect(
      archiveRetentionPhase({
        retain_until: "not-a-date",
        recovery_until: "invalid",
      }),
    ).toBe("expired");
  });
});
