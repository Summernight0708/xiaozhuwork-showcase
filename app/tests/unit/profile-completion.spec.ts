import { describe, expect, it } from "vitest";

import {
  displayNameError,
  missingProjectIdentity,
  profileNeedsCompletion,
  safeReturnPath,
} from "@/domain/profile-completion";

describe("profile completion", () => {
  it("requires only a non-empty trimmed display name globally", () => {
    expect(profileNeedsCompletion(null)).toBe(true);
    expect(profileNeedsCompletion({ display_name: "   " })).toBe(true);
    expect(profileNeedsCompletion({ display_name: "小林" })).toBe(false);
  });

  it("validates display names from 1 through 30 characters", () => {
    expect(displayNameError("  ")).toBeTruthy();
    expect(displayNameError("小林")).toBeNull();
    expect(displayNameError("a".repeat(30))).toBeNull();
    expect(displayNameError("a".repeat(31))).toBeTruthy();
  });

  it("accepts a safe local return target and rejects external-looking targets", () => {
    expect(safeReturnPath("/invite/token?x=1")).toBe("/invite/token?x=1");
    expect(safeReturnPath("//evil.example")).toBe("/projects");
    expect(safeReturnPath("https://evil.example")).toBe("/projects");
  });

  it("does not globally require real name or student number", () => {
    expect(
      missingProjectIdentity(
        { real_name: null, student_number: null },
        { requireRealName: false, requireStudentNumber: false },
      ),
    ).toEqual({ realName: false, studentNumber: false });
  });

  it("requires real name and student number only when the project asks for them", () => {
    expect(
      missingProjectIdentity(
        { real_name: null, student_number: "2026123456" },
        { requireRealName: true, requireStudentNumber: true },
      ),
    ).toEqual({ realName: true, studentNumber: false });
  });
});
