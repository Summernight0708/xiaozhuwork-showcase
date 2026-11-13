import { describe, expect, it } from "vitest";

import { canActAsTaskParticipant } from "@/domain/task-actions";

describe("task action access", () => {
  it("keeps observers read-only even when stale task facts still name them", () => {
    expect(
      canActAsTaskParticipant({
        role: "observer",
        currentUserId: "user-1",
        targetUserId: "user-1",
      }),
    ).toBe(false);
  });

  it("allows an active non-observer to act only on their own assignment or offer", () => {
    expect(
      canActAsTaskParticipant({
        role: "member",
        currentUserId: "user-1",
        targetUserId: "user-1",
      }),
    ).toBe(true);
    expect(
      canActAsTaskParticipant({
        role: "admin",
        currentUserId: "user-1",
        targetUserId: "user-2",
      }),
    ).toBe(false);
  });
});
