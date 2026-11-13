import { describe, expect, it } from "vitest";

import {
  AUTH_PASSWORD_MIN_LENGTH,
  AUTH_VISIBLE_JITTER_MS,
  AUTH_VISIBLE_MIN_MS,
  validateNewPassword,
  visibleResponseDelayMs,
} from "@/domain/auth-security";

describe("auth security policy", () => {
  it("freezes the reviewed password and timing constants", () => {
    expect(AUTH_PASSWORD_MIN_LENGTH).toBe(8);
    expect(AUTH_VISIBLE_MIN_MS).toBe(600);
    expect(AUTH_VISIBLE_JITTER_MS).toBe(150);
  });

  it("validates password length and confirmation", () => {
    expect(validateNewPassword("1234567", "1234567")).toBe("too_short");
    expect(validateNewPassword("12345678", "87654321")).toBe("mismatch");
    expect(validateNewPassword("12345678", "12345678")).toBe("ok");
  });

  it("keeps account-sensitive visible delay within the reviewed window", () => {
    expect(visibleResponseDelayMs(1_000, 1_000, 0)).toBe(600);
    expect(visibleResponseDelayMs(1_000, 1_000, 1)).toBe(750);
    expect(visibleResponseDelayMs(1_000, 1_100, 0)).toBe(500);
    expect(visibleResponseDelayMs(1_000, 2_000, 0.5)).toBe(0);
  });
});
