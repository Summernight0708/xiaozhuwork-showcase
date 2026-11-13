import { describe, expect, it } from "vitest";

import {
  formatAccountEntitlement,
  formatProjectEntitlement,
} from "@/domain/entitlements";

describe("project entitlement presentation", () => {
  it("presents effective Free projects without an expiry label", () => {
    expect(
      formatProjectEntitlement({
        projectId: "project-1",
        plan: "free",
        state: "free",
        source: "none",
        graceExpiresAt: null,
      }),
    ).toEqual({
      label: "Free",
      detail: "当前项目按 Free 权益运行。",
      graceExpiryLabel: null,
      isPro: false,
      isGrace: false,
    });
  });

  it("presents active effective Pro without leaking account expiry", () => {
    expect(
      formatProjectEntitlement({
        projectId: "project-1",
        plan: "pro",
        state: "active",
        source: "account_member",
        graceExpiresAt: null,
      }),
    ).toEqual({
      label: "Pro",
      detail: "由项目成员 Pro 提供。",
      graceExpiryLabel: null,
      isPro: true,
      isGrace: false,
    });
  });

  it("presents grace using only the project grace deadline", () => {
    const result = formatProjectEntitlement({
      projectId: "project-1",
      plan: "pro",
      state: "grace",
      source: "grace",
      graceExpiresAt: "2027-06-30T00:00:00.000Z",
    });

    expect(result.label).toBe("Pro · 宽限期");
    expect(result.detail).toContain("宽限结束后");
    expect(result.isPro).toBe(true);
    expect(result.isGrace).toBe(true);
    expect(result.graceExpiryLabel).toContain("2027");
  });
});

describe("account entitlement presentation", () => {
  it("keeps active account Pro separate from project grace semantics", () => {
    const result = formatAccountEntitlement({
      plan: "pro",
      state: "active",
      startsAt: "2026-10-01T00:00:00.000Z",
      expiresAt: "2027-01-01T00:00:00.000Z",
      version: 2,
    });

    expect(result.label).toBe("Pro");
    expect(result.currentPlanLabel).toBe("Pro");
    expect(result.detail).toContain("有效期至");
    expect(result.detail).not.toContain("宽限");
  });

  it.each([
    ["free", "Free", "当前有效方案为 Free"],
    ["scheduled", "Pro 已安排", "将于"],
    ["expired", "Pro 已到期", "当前有效方案为 Free"],
    ["cancelled", "Pro 已取消", "当前有效方案为 Free"],
  ] as const)("presents account state %s", (state, label, detail) => {
    const result = formatAccountEntitlement({
      plan: "free",
      state,
      startsAt: state === "free" ? null : "2026-12-01T00:00:00.000Z",
      expiresAt: state === "free" ? null : "2027-01-01T00:00:00.000Z",
      version: state === "free" ? 0 : 2,
    });

    expect(result.label).toBe(label);
    expect(result.detail).toContain(detail);
    expect(result.currentPlanLabel).toBe("Free");
  });
});
