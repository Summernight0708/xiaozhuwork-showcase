import { describe, expect, it } from "vitest";

import {
  inviteJoinCommandSnapshot,
  inviteJoinExpectedVersion,
} from "@/domain/invitations";

describe("invite join version contract", () => {
  it("uses zero for approval requests and the invitation version for direct joins", () => {
    expect(
      inviteJoinExpectedVersion({ mode: "approval", invitationVersion: 4 }),
    ).toBe(0);
    expect(
      inviteJoinExpectedVersion({ mode: "direct", invitationVersion: 4 }),
    ).toBe(4);
  });

  it("snapshots the invite token and version for a logical retry", () => {
    const snapshot = inviteJoinCommandSnapshot("token-a", {
      mode: "direct",
      invitationVersion: 7,
    });

    expect(snapshot).toEqual({ token: "token-a", expectedVersion: 7 });
  });
});
