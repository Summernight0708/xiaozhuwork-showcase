import { describe, expect, it, vi } from "vitest";

import {
  requestEmailCode,
  requestRecoveryOtp,
  requestSignupOtp,
  setAuthenticatedPassword,
  signInWithEmailPassword,
  signOut,
  verifyEmailCode,
  verifyEmailOtp,
  type EmailAuthPort,
} from "../../src/lib/email-auth";

function createAuthPort(overrides: Partial<EmailAuthPort> = {}): EmailAuthPort {
  return {
    signInWithOtp: vi.fn().mockResolvedValue({ error: null }),
    verifyOtp: vi.fn().mockResolvedValue({
      data: {
        session: { access_token: "session-token" },
        user: { id: "user-1" },
      },
      error: null,
    }),
    signInWithPassword: vi.fn().mockResolvedValue({
      data: {
        session: { access_token: "password-session" },
        user: { id: "user-1" },
      },
      error: null,
    }),
    updateUser: vi.fn().mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    }),
    signOut: vi.fn().mockResolvedValue({ error: null }),
    ...overrides,
  };
}

describe("email authentication adapter", () => {
  it("requests signup OTP with shouldCreateUser=true", async () => {
    const auth = createAuthPort();

    await expect(
      requestSignupOtp(auth, "  student@example.edu  "),
    ).resolves.toEqual({ ok: true });

    expect(auth.signInWithOtp).toHaveBeenCalledWith({
      email: "student@example.edu",
      options: { shouldCreateUser: true },
    });
  });

  it("requests recovery OTP with shouldCreateUser=false", async () => {
    const auth = createAuthPort();

    await expect(
      requestRecoveryOtp(auth, "student@example.edu"),
    ).resolves.toEqual({ ok: true });

    expect(auth.signInWithOtp).toHaveBeenCalledWith({
      email: "student@example.edu",
      options: { shouldCreateUser: false },
    });
  });

  it("keeps requestEmailCode as the signup-compatible alias", async () => {
    const auth = createAuthPort();

    await expect(
      requestEmailCode(auth, "student@example.edu"),
    ).resolves.toEqual({ ok: true });

    expect(auth.signInWithOtp).toHaveBeenCalledWith({
      email: "student@example.edu",
      options: { shouldCreateUser: true },
    });
  });

  it("rejects malformed email without calling Supabase", async () => {
    const auth = createAuthPort();

    await expect(requestSignupOtp(auth, "not-an-email")).resolves.toEqual({
      ok: false,
      code: "INVALID_EMAIL",
    });
    expect(auth.signInWithOtp).not.toHaveBeenCalled();
  });

  it("verifies only six-digit email OTP and returns the authenticated session", async () => {
    const auth = createAuthPort();

    const result = await verifyEmailOtp(auth, "student@example.edu", "004281");

    expect(result).toEqual({
      ok: true,
      session: { access_token: "session-token" },
      user: { id: "user-1" },
    });
    expect(auth.verifyOtp).toHaveBeenCalledWith({
      email: "student@example.edu",
      token: "004281",
      type: "email",
    });
  });

  it("keeps verifyEmailCode as the compatibility alias", async () => {
    const auth = createAuthPort();

    await expect(
      verifyEmailCode(auth, "student@example.edu", "004281"),
    ).resolves.toMatchObject({ ok: true });
  });

  it("rejects malformed OTP without calling Supabase", async () => {
    const auth = createAuthPort();

    await expect(
      verifyEmailOtp(auth, "student@example.edu", "4281"),
    ).resolves.toEqual({
      ok: false,
      code: "INVALID_CODE",
    });
    expect(auth.verifyOtp).not.toHaveBeenCalled();
  });

  it("signs in with email and password", async () => {
    const auth = createAuthPort();

    await expect(
      signInWithEmailPassword(auth, " student@example.edu ", "password-1"),
    ).resolves.toEqual({
      ok: true,
      session: { access_token: "password-session" },
      user: { id: "user-1" },
    });

    expect(auth.signInWithPassword).toHaveBeenCalledWith({
      email: "student@example.edu",
      password: "password-1",
    });
  });

  it("rejects an empty password before calling Supabase", async () => {
    const auth = createAuthPort();

    await expect(
      signInWithEmailPassword(auth, "student@example.edu", ""),
    ).resolves.toEqual({
      ok: false,
      code: "INVALID_PASSWORD",
    });
    expect(auth.signInWithPassword).not.toHaveBeenCalled();
  });

  it("sets password only on the authenticated user", async () => {
    const auth = createAuthPort();

    await expect(
      setAuthenticatedPassword(auth, "new-password"),
    ).resolves.toEqual({
      ok: true,
      user: { id: "user-1" },
    });

    expect(auth.updateUser).toHaveBeenCalledWith({
      password: "new-password",
    });
  });

  it("normalizes rate-limit errors", async () => {
    const error = Object.assign(new Error("Too many requests"), {
      status: 429,
    });
    const auth = createAuthPort({
      signInWithOtp: vi.fn().mockResolvedValue({ error }),
    });

    await expect(
      requestSignupOtp(auth, "student@example.edu"),
    ).resolves.toEqual({
      ok: false,
      code: "RATE_LIMITED",
    });
  });

  it("normalizes invalid login credentials", async () => {
    const error = Object.assign(new Error("Invalid login credentials"), {
      status: 400,
    });
    const auth = createAuthPort({
      signInWithPassword: vi.fn().mockResolvedValue({
        data: { session: null, user: null },
        error,
      }),
    });

    await expect(
      signInWithEmailPassword(auth, "student@example.edu", "wrong-pass"),
    ).resolves.toEqual({
      ok: false,
      code: "INVALID_CREDENTIALS",
    });
  });

  it("normalizes password-policy rejection", async () => {
    const error = Object.assign(
      new Error("Password should be at least 8 characters"),
      { status: 422 },
    );
    const auth = createAuthPort({
      updateUser: vi.fn().mockResolvedValue({
        data: { user: null },
        error,
      }),
    });

    await expect(setAuthenticatedPassword(auth, "short")).resolves.toEqual({
      ok: false,
      code: "PASSWORD_POLICY_REJECTED",
    });
  });

  it("signs out without leaking provider errors", async () => {
    const auth = createAuthPort({
      signOut: vi
        .fn()
        .mockResolvedValue({ error: new Error("private provider detail") }),
    });

    await expect(signOut(auth)).resolves.toEqual({
      ok: false,
      code: "AUTH_UNAVAILABLE",
    });
  });
});
