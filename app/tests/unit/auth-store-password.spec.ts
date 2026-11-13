import { createPinia, setActivePinia } from "pinia";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  backend: {
    client: {
      auth: {},
      rpc: vi.fn(),
    },
  },
  requestSignupOtp: vi.fn(),
  requestRecoveryOtp: vi.fn(),
  verifyEmailOtp: vi.fn(),
  signInWithEmailPassword: vi.fn(),
  setAuthenticatedPassword: vi.fn(),
  performSignOut: vi.fn(),
  getProfile: vi.fn(),
}));

vi.mock("@/services/backend", () => ({
  getBackend: () => mocks.backend,
}));

vi.mock("@/services/repository", () => ({
  createRepository: () => ({
    getProfile: mocks.getProfile,
  }),
}));

vi.mock("@/lib/email-auth", () => ({
  requestEmailCode: mocks.requestSignupOtp,
  requestSignupOtp: mocks.requestSignupOtp,
  requestRecoveryOtp: mocks.requestRecoveryOtp,
  verifyEmailCode: mocks.verifyEmailOtp,
  verifyEmailOtp: mocks.verifyEmailOtp,
  signInWithEmailPassword: mocks.signInWithEmailPassword,
  setAuthenticatedPassword: mocks.setAuthenticatedPassword,
  signOut: mocks.performSignOut,
}));

import { useAuthStore } from "@/stores/auth";

describe("password auth store orchestration", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.useRealTimers();
    vi.clearAllMocks();
    mocks.getProfile.mockResolvedValue({
      id: "user-1",
      display_name: "Student",
    });
    mocks.performSignOut.mockResolvedValue({ ok: true });
  });

  it("does not delay successful password login", async () => {
    mocks.signInWithEmailPassword.mockResolvedValue({
      ok: true,
      user: { id: "user-1" },
      session: { access_token: "token" },
    });
    const store = useAuthStore();

    await expect(
      store.loginWithPassword("student@example.edu", "password-1"),
    ).resolves.toMatchObject({ ok: true });

    expect(store.user?.id).toBe("user-1");
    expect(mocks.getProfile).toHaveBeenCalledWith("user-1");
  });

  it("delays account-sensitive login failure", async () => {
    vi.useFakeTimers();
    mocks.signInWithEmailPassword.mockResolvedValue({
      ok: false,
      code: "INVALID_CREDENTIALS",
    });
    const store = useAuthStore();

    let settled = false;
    const promise = store
      .loginWithPassword("student@example.edu", "wrong-pass")
      .finally(() => {
        settled = true;
      });

    await Promise.resolve();
    expect(settled).toBe(false);
    await vi.advanceTimersByTimeAsync(750);
    await expect(promise).resolves.toEqual({
      ok: false,
      code: "INVALID_CREDENTIALS",
    });
  });

  it("delays recovery request success to the same visible window", async () => {
    vi.useFakeTimers();
    mocks.requestRecoveryOtp.mockResolvedValue({ ok: true });
    const store = useAuthStore();

    let settled = false;
    const promise = store
      .requestRecoveryCode("student@example.edu")
      .finally(() => {
        settled = true;
      });

    await Promise.resolve();
    expect(settled).toBe(false);
    await vi.advanceTimersByTimeAsync(750);
    await expect(promise).resolves.toEqual({ ok: true });
  });

  it("masks recovery account-existence errors as the same visible success", async () => {
    vi.useFakeTimers();
    mocks.requestRecoveryOtp.mockResolvedValue({
      ok: false,
      code: "AUTH_UNAVAILABLE",
    });
    const store = useAuthStore();

    const promise = store.requestRecoveryCode("missing@example.edu");
    await vi.advanceTimersByTimeAsync(750);

    await expect(promise).resolves.toEqual({ ok: true });
  });

  it("keeps verified OTP session pending until password is written", async () => {
    mocks.verifyEmailOtp.mockResolvedValue({
      ok: true,
      user: { id: "user-1" },
      session: { access_token: "otp-session" },
    });
    const store = useAuthStore();

    await expect(
      store.verifyPasswordSetupCode("student@example.edu", "123456"),
    ).resolves.toMatchObject({ ok: true });

    expect(store.pendingPasswordSetup).toBe(true);
    expect(store.user).toBeNull();
    expect(store.isAuthenticated).toBe(false);
  });

  it("signs out and clears pending auth when password update fails", async () => {
    mocks.verifyEmailOtp.mockResolvedValue({
      ok: true,
      user: { id: "user-1" },
      session: { access_token: "otp-session" },
    });
    mocks.setAuthenticatedPassword.mockResolvedValue({
      ok: false,
      code: "PASSWORD_POLICY_REJECTED",
    });
    const store = useAuthStore();
    await store.verifyPasswordSetupCode("student@example.edu", "123456");

    await expect(
      store.setVerifiedPassword("12345678", "12345678"),
    ).resolves.toEqual({
      ok: false,
      code: "PASSWORD_POLICY_REJECTED",
    });

    expect(mocks.performSignOut).toHaveBeenCalledTimes(1);
    expect(store.pendingPasswordSetup).toBe(false);
    expect(store.user).toBeNull();
  });

  it("rejects mismatched password before calling Supabase", async () => {
    const store = useAuthStore();

    await expect(
      store.setVerifiedPassword("12345678", "87654321"),
    ).resolves.toEqual({
      ok: false,
      code: "PASSWORD_MISMATCH",
    });

    expect(mocks.setAuthenticatedPassword).not.toHaveBeenCalled();
  });
});
