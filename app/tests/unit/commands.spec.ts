import { describe, expect, it } from "vitest";

import { isCommandFailure, isCommandSuccess } from "@/types/commands";

describe("command result helpers", () => {
  it("recognizes successful command results", () => {
    expect(
      isCommandSuccess({
        ok: true,
        data: { id: "project-1" },
        requestId: "request-1",
        replayed: false,
        aggregateType: "project",
        aggregateId: "project-1",
        aggregateVersion: 1,
      }),
    ).toBe(true);
  });

  it("recognizes failed command results", () => {
    expect(
      isCommandFailure({
        ok: false,
        code: "NOT_AUTHORIZED",
        requestId: "request-1",
        replayed: false,
      }),
    ).toBe(true);
  });
});
