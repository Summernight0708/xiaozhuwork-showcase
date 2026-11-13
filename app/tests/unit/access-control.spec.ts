import { describe, expect, it } from "vitest";

import {
  capabilitiesForMembership,
  capabilitiesForRole,
  normalizeProjectRole,
} from "@/domain/access-control";

describe("project role capabilities", () => {
  it("keeps the four approved UI roles distinct", () => {
    expect(normalizeProjectRole({ role: "leader", isObserver: false })).toBe(
      "leader",
    );
    expect(normalizeProjectRole({ role: "admin", isObserver: false })).toBe(
      "admin",
    );
    expect(normalizeProjectRole({ role: "member", isObserver: false })).toBe(
      "member",
    );
    expect(normalizeProjectRole({ role: "member", isObserver: true })).toBe(
      "observer",
    );
  });

  it("fails closed when no active project membership is available", () => {
    const capabilities = capabilitiesForMembership(null);
    expect(
      Object.values(capabilities).every((allowed) => allowed === false),
    ).toBe(true);
  });

  it("treats observer as read-only UX and still leaves server as authority", () => {
    const observer = capabilitiesForRole("observer");
    expect(observer.canCreateTask).toBe(false);
    expect(observer.canUploadFile).toBe(false);
    expect(observer.canReviewSubmission).toBe(false);
    expect(observer.canManageInvites).toBe(false);
  });

  it("only gates regular members when task creation is disabled", () => {
    expect(
      capabilitiesForMembership({ role: "member", isObserver: false }, false)
        .canCreateTask,
    ).toBe(false);
    expect(
      capabilitiesForMembership({ role: "leader", isObserver: false }, false)
        .canCreateTask,
    ).toBe(true);
    expect(
      capabilitiesForMembership({ role: "admin", isObserver: false }, false)
        .canCreateTask,
    ).toBe(true);
    expect(
      capabilitiesForMembership({ role: "observer", isObserver: true }, true)
        .canCreateTask,
    ).toBe(false);
    expect(
      capabilitiesForMembership({ role: "member", isObserver: false })
        .canCreateTask,
    ).toBe(true);
  });

  it("maps the formal four-role backend capabilities without granting admin governance powers", () => {
    const leader = capabilitiesForRole("leader");
    const member = capabilitiesForRole("member");
    expect(leader.canCreateTask).toBe(true);
    expect(leader.canManageInvites).toBe(true);
    expect(member.canCreateTask).toBe(true);
    expect(member.canUploadFile).toBe(true);
    const admin = capabilitiesForRole("admin");
    expect(admin.canManageInvites).toBe(false);
    expect(admin.canReviewJoinRequest).toBe(false);
    expect(admin.canUploadFile).toBe(true);
    expect(admin.canCreateTask).toBe(true);
    expect(admin.canManageMembers).toBe(true);
    expect(admin.canUpdateProjectSettings).toBe(false);
    expect(admin.canMarkFinalFiles).toBe(false);
    expect(leader.canUpdateProjectSettings).toBe(true);
    expect(leader.canMarkFinalFiles).toBe(true);
  });
});
