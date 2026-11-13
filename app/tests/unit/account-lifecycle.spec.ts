import { describe, expect, it } from "vitest";
import {
  explainAccountDeletionError,
  mayCancelDeletion,
  type AccountLifecycleStatus,
} from "@/features/account-lifecycle/repository";

function status(
  patch: Partial<AccountLifecycleStatus> = {},
): AccountLifecycleStatus {
  return {
    state: "pending",
    version: 1,
    cancelUntil: "2026-12-01T00:00:00Z",
    ...patch,
  };
}

describe("account lifecycle controls", () => {
  it("allows a bounded self-cancel strictly before the authoritative deadline", () => {
    expect(
      mayCancelDeletion(status(), Date.parse("2026-11-30T23:59:59Z")),
    ).toBe(true);
    expect(
      mayCancelDeletion(status(), Date.parse("2026-12-01T00:00:00Z")),
    ).toBe(false);
    expect(mayCancelDeletion(status({ state: "blocked" }), 0)).toBe(false);
    expect(
      mayCancelDeletion(status({ redactedAt: "2026-11-01T00:00:00Z" }), 0),
    ).toBe(false);
    expect(mayCancelDeletion(status({ cancelUntil: "invalid" }), 0)).toBe(
      false,
    );
    expect(
      mayCancelDeletion(status({ authRevokedAt: "2026-11-01T00:00:00Z" }), 0),
    ).toBe(false);
    expect(mayCancelDeletion(status({ cancelUntil: undefined }), 0)).toBe(
      false,
    );
  });
  it("reports authoritative business blockers rather than a generic error", () => {
    expect(
      explainAccountDeletionError({
        ok: false,
        code: "REAUTHENTICATION_REQUIRED",
      }),
    ).toContain("重新登录原账号");
    expect(
      explainAccountDeletionError({
        ok: false,
        code: "ACCOUNT_DELETION_BLOCKED",
        details: { reason: "仍为唯一组长" },
      }),
    ).toBe("仍为唯一组长");
    expect(
      explainAccountDeletionError({ ok: false, code: "STALE_VERSION" }),
    ).toContain("刷新");
    expect(
      explainAccountDeletionError({
        ok: false,
        code: "RETENTION_WINDOW_EXPIRED",
      }),
    ).toContain("期限");
  });
});
