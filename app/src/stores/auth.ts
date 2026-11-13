import type { User } from "@supabase/supabase-js";
import { defineStore } from "pinia";
import { computed, ref } from "vue";

import {
  requestEmailCode,
  requestRecoveryOtp,
  requestSignupOtp,
  setAuthenticatedPassword,
  signInWithEmailPassword,
  signOut as performSignOut,
  verifyEmailCode,
  verifyEmailOtp,
  type EmailAuthErrorCode,
} from "@/lib/email-auth";
import {
  validateNewPassword,
  waitForVisibleResponseWindow,
} from "@/domain/auth-security";
import { getBackend } from "@/services/backend";
import { createRepository } from "@/services/repository";
import { syncSentryUser } from "@/services/telemetry/sentry";
import type { ProfileRow } from "@/types/ui";

type PasswordSetupValidationCode = "PASSWORD_TOO_SHORT" | "PASSWORD_MISMATCH";

export const useAuthStore = defineStore("auth", () => {
  const initialized = ref(false);
  const configured = ref(true);
  const loading = ref(false);
  const user = ref<User | null>(null);
  const profile = ref<ProfileRow | null>(null);
  const error = ref<string | null>(null);
  const pendingPasswordSetup = ref(false);
  const pendingVerifiedUser = ref<User | null>(null);
  // Ignore older profile reads after a newer profile mutation begins.
  let profileRevision = 0;

  const isAuthenticated = computed(
    () => !!user.value && !pendingPasswordSetup.value,
  );

  async function refreshProfile() {
    const backend = getBackend();
    if (!backend || !user.value) {
      profile.value = null;
      return;
    }
    const revision = profileRevision;
    try {
      const nextProfile = await createRepository(backend.client).getProfile(
        user.value.id,
      );
      if (revision === profileRevision) profile.value = nextProfile;
    } catch (cause) {
      // A pending deletion is intentionally blocked by restrictive profile
      // RLS. Preserve the authenticated cancellation route instead of
      // treating the missing profile as a nickname-completion problem.
      const { data, error: lifecycleError } = await backend.client.rpc(
        "get_account_lifecycle_status",
      );
      const response = data as {
        ok?: boolean;
        data?: { state?: string };
      } | null;
      if (
        !lifecycleError &&
        response?.ok &&
        ["pending", "blocked", "redacted"].includes(response.data?.state ?? "")
      ) {
        if (revision === profileRevision) profile.value = null;
        return;
      }
      throw cause;
    }
  }

  function clearPendingPasswordSetup() {
    pendingPasswordSetup.value = false;
    pendingVerifiedUser.value = null;
  }

  async function initialize() {
    if (initialized.value) return;
    const backend = getBackend();
    if (!backend) {
      configured.value = false;
      initialized.value = true;
      return;
    }
    configured.value = true;
    const { data } = await backend.client.auth.getSession();
    user.value = data.session?.user ?? null;
    syncSentryUser(user.value?.id ?? null);
    if (user.value) await refreshProfile();
    backend.client.auth.onAuthStateChange((_event, session) => {
      if (pendingPasswordSetup.value) {
        user.value = null;
        profile.value = null;
        if (session?.user) pendingVerifiedUser.value = session.user;
        return;
      }
      user.value = session?.user ?? null;
      syncSentryUser(user.value?.id ?? null);
      if (user.value) void refreshProfile();
      else profile.value = null;
    });
    initialized.value = true;
  }

  async function requestCode(email: string) {
    const backend = getBackend();
    if (!backend)
      return { ok: false as const, code: "AUTH_UNAVAILABLE" as const };
    loading.value = true;
    error.value = null;
    try {
      return await requestEmailCode(backend.client.auth, email);
    } finally {
      loading.value = false;
    }
  }

  async function verifyCode(email: string, code: string) {
    const backend = getBackend();
    if (!backend)
      return { ok: false as const, code: "AUTH_UNAVAILABLE" as const };
    loading.value = true;
    error.value = null;
    try {
      const result = await verifyEmailCode(backend.client.auth, email, code);
      if (result.ok) {
        user.value = result.user;
        syncSentryUser(result.user.id);
        await refreshProfile();
      }
      return result;
    } finally {
      loading.value = false;
    }
  }

  async function loginWithPassword(email: string, password: string) {
    const backend = getBackend();
    if (!backend)
      return { ok: false as const, code: "AUTH_UNAVAILABLE" as const };

    loading.value = true;
    error.value = null;
    const startedAt = Date.now();
    try {
      const result = await signInWithEmailPassword(
        backend.client.auth,
        email,
        password,
      );
      if (result.ok) {
        clearPendingPasswordSetup();
        user.value = result.user;
        await refreshProfile();
        return result;
      }

      if (
        result.code !== "INVALID_EMAIL" &&
        result.code !== "INVALID_PASSWORD"
      ) {
        await waitForVisibleResponseWindow(startedAt);
      }
      return result;
    } finally {
      loading.value = false;
    }
  }

  async function requestSignupCode(email: string) {
    return requestPasswordSetupCode(email, "signup");
  }

  async function requestRecoveryCode(email: string) {
    return requestPasswordSetupCode(email, "recovery");
  }

  async function requestPasswordSetupCode(
    email: string,
    mode: "signup" | "recovery",
  ) {
    const backend = getBackend();
    if (!backend)
      return { ok: false as const, code: "AUTH_UNAVAILABLE" as const };

    loading.value = true;
    error.value = null;
    const startedAt = Date.now();
    try {
      const result =
        mode === "signup"
          ? await requestSignupOtp(backend.client.auth, email)
          : await requestRecoveryOtp(backend.client.auth, email);

      if (result.ok || result.code !== "INVALID_EMAIL") {
        await waitForVisibleResponseWindow(startedAt);
      }
      if (
        mode === "recovery" &&
        !result.ok &&
        result.code === "AUTH_UNAVAILABLE"
      ) {
        return { ok: true as const };
      }
      return result;
    } finally {
      loading.value = false;
    }
  }

  async function verifyPasswordSetupCode(email: string, code: string) {
    const backend = getBackend();
    if (!backend)
      return { ok: false as const, code: "AUTH_UNAVAILABLE" as const };

    loading.value = true;
    error.value = null;
    pendingPasswordSetup.value = true;
    pendingVerifiedUser.value = null;
    user.value = null;
    profile.value = null;

    try {
      const result = await verifyEmailOtp(backend.client.auth, email, code);
      if (!result.ok) {
        clearPendingPasswordSetup();
        return result;
      }

      pendingVerifiedUser.value = result.user;
      return { ok: true as const };
    } finally {
      loading.value = false;
    }
  }

  async function setVerifiedPassword(
    password: string,
    confirmation: string,
  ): Promise<
    | { ok: true }
    | {
        ok: false;
        code: EmailAuthErrorCode | PasswordSetupValidationCode;
      }
  > {
    const validation = validateNewPassword(password, confirmation);
    if (validation === "too_short") {
      return { ok: false, code: "PASSWORD_TOO_SHORT" };
    }
    if (validation === "mismatch") {
      return { ok: false, code: "PASSWORD_MISMATCH" };
    }

    const backend = getBackend();
    if (!backend || !pendingPasswordSetup.value) {
      return { ok: false, code: "AUTH_UNAVAILABLE" };
    }

    loading.value = true;
    error.value = null;
    try {
      const result = await setAuthenticatedPassword(
        backend.client.auth,
        password,
      );
      if (!result.ok) {
        await performSignOut(backend.client.auth);
        clearPendingPasswordSetup();
        user.value = null;
        profile.value = null;
        return result;
      }

      const verifiedUser = result.user ?? pendingVerifiedUser.value;
      clearPendingPasswordSetup();
      user.value = verifiedUser;
      await refreshProfile();
      return { ok: true };
    } catch {
      await performSignOut(backend.client.auth);
      clearPendingPasswordSetup();
      user.value = null;
      profile.value = null;
      return { ok: false, code: "AUTH_UNAVAILABLE" };
    } finally {
      loading.value = false;
    }
  }

  async function abortVerifiedAuth() {
    const backend = getBackend();
    if (backend && pendingPasswordSetup.value) {
      await performSignOut(backend.client.auth);
    }
    clearPendingPasswordSetup();
    user.value = null;
    profile.value = null;
  }

  async function logout() {
    const backend = getBackend();
    if (!backend) return;
    await performSignOut(backend.client.auth);
    clearPendingPasswordSetup();
    user.value = null;
    profile.value = null;
    syncSentryUser(null);
  }

  async function saveDisplayName(displayName: string) {
    const backend = getBackend();
    if (!backend || !user.value)
      throw new Error("Login required to save profile");
    const mutationRevision = ++profileRevision;
    const nextProfile = await createRepository(backend.client).updateProfile(
      user.value.id,
      displayName,
    );
    if (profileRevision === mutationRevision) {
      profile.value = nextProfile;
      profileRevision += 1;
    }
  }

  async function saveProfile(input: {
    displayName: string;
    realName?: string;
    studentNumber?: string;
  }) {
    const backend = getBackend();
    if (!backend || !user.value)
      throw new Error("Login required to save profile");
    const mutationRevision = ++profileRevision;
    const { data, error: updateError } = await backend.client
      .from("profiles")
      .update({
        display_name: input.displayName.trim() || null,
        real_name: input.realName?.trim() || null,
        student_number: input.studentNumber?.trim() || null,
      })
      .eq("id", user.value.id)
      .select("*")
      .single();
    if (updateError) throw new Error("Profile update failed");
    if (profileRevision === mutationRevision) {
      profile.value = data;
      profileRevision += 1;
    }
  }

  async function requestEmailChange(nextEmail: string) {
    const backend = getBackend();
    if (!backend) return { ok: false as const };
    const { error: updateError } = await backend.client.auth.updateUser({
      email: nextEmail.trim(),
    });
    return { ok: !updateError } as const;
  }

  return {
    initialized,
    configured,
    loading,
    user,
    profile,
    error,
    pendingPasswordSetup,
    isAuthenticated,
    initialize,
    requestCode,
    verifyCode,
    loginWithPassword,
    requestSignupCode,
    requestRecoveryCode,
    verifyPasswordSetupCode,
    setVerifiedPassword,
    abortVerifiedAuth,
    logout,
    refreshProfile,
    saveDisplayName,
    saveProfile,
    requestEmailChange,
  };
});
