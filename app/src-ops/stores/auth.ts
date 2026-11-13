import type { Session } from "@supabase/supabase-js";
import { defineStore } from "pinia";
import { computed, ref } from "vue";

import { callOpsApi, type OpsApiErrorCode } from "@ops/lib/ops-api";
import { getOpsSupabase } from "@ops/lib/supabase";

type AuthResult = { ok: true } | { ok: false; code: OpsApiErrorCode };

export const useOpsAuthStore = defineStore("ops-auth", () => {
  const initialized = ref(false);
  const loading = ref(false);
  const session = ref<Session | null>(null);
  const authorized = ref(false);
  let subscribed = false;

  const isAuthenticated = computed(() => session.value !== null);
  const isAuthorized = computed(
    () => session.value !== null && authorized.value,
  );

  async function clearSession(signOut = false): Promise<void> {
    if (signOut) {
      try {
        await getOpsSupabase().auth.signOut();
      } catch {
        // Local state still fails closed if provider sign-out is unavailable.
      }
    }
    session.value = null;
    authorized.value = false;
  }

  async function gate(nextSession: Session): Promise<AuthResult> {
    const result = await callOpsApi(
      { action: "access" },
      nextSession.access_token,
    );
    if (!result.ok) {
      await clearSession(true);
      return result;
    }

    const userId = (result.data as { userId?: unknown } | undefined)?.userId;
    if (typeof userId !== "string" || userId !== nextSession.user.id) {
      await clearSession(true);
      return { ok: false, code: "SERVICE_UNAVAILABLE" };
    }

    session.value = nextSession;
    authorized.value = true;
    return { ok: true };
  }

  async function initialize(): Promise<void> {
    if (initialized.value) return;
    const supabase = getOpsSupabase();

    try {
      const { data, error } = await supabase.auth.getSession();
      if (!error && data.session) {
        session.value = data.session;
        await gate(data.session);
      }

      if (!subscribed) {
        subscribed = true;
        supabase.auth.onAuthStateChange((_event, nextSession) => {
          if (!nextSession) {
            session.value = null;
            authorized.value = false;
            return;
          }
          session.value = nextSession;
          authorized.value = false;
          void gate(nextSession);
        });
      }
    } catch {
      session.value = null;
      authorized.value = false;
    } finally {
      initialized.value = true;
    }
  }

  async function login(email: string, password: string): Promise<AuthResult> {
    if (loading.value) return { ok: false, code: "SERVICE_UNAVAILABLE" };
    const normalizedEmail = email.trim();
    if (!normalizedEmail || !password) {
      return { ok: false, code: "VALIDATION_FAILED" };
    }

    loading.value = true;
    authorized.value = false;
    try {
      const { data, error } = await getOpsSupabase().auth.signInWithPassword({
        email: normalizedEmail,
        password,
      });
      if (error || !data.session) {
        await clearSession(false);
        return { ok: false, code: "UNAUTHENTICATED" };
      }

      session.value = data.session;
      return await gate(data.session);
    } catch {
      await clearSession(false);
      return { ok: false, code: "SERVICE_UNAVAILABLE" };
    } finally {
      loading.value = false;
    }
  }

  async function logout(): Promise<void> {
    await clearSession(true);
  }

  return {
    initialized,
    loading,
    session,
    isAuthenticated,
    isAuthorized,
    initialize,
    login,
    logout,
  };
});
