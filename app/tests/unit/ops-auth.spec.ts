import { createPinia, setActivePinia } from "pinia";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getSession: vi.fn(),
  signInWithPassword: vi.fn(),
  signOut: vi.fn(),
  onAuthStateChange: vi.fn(() => ({
    data: { subscription: { unsubscribe: vi.fn() } },
  })),
  opsApi: vi.fn(),
}));

vi.mock("@ops/lib/supabase", () => ({
  getOpsSupabase: () => ({
    auth: {
      getSession: mocks.getSession,
      signInWithPassword: mocks.signInWithPassword,
      signOut: mocks.signOut,
      onAuthStateChange: mocks.onAuthStateChange,
    },
  }),
}));

vi.mock("@ops/lib/ops-api", () => ({
  callOpsApi: mocks.opsApi,
}));

import { useOpsAuthStore } from "@ops/stores/auth";
import {
  readSupabaseBrowserEnvironment,
  type SupabaseBrowserEnv,
} from "@shared/supabase/environment";

const session = {
  access_token: "user-token",
  user: { id: "0a000000-0000-4000-8000-000000000001" },
};

describe("Ops independent auth gate", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    mocks.getSession.mockResolvedValue({
      data: { session: null },
      error: null,
    });
    mocks.signOut.mockResolvedValue({ error: null });
  });

  it("parses only public Supabase browser environment", () => {
    const env = {
      VITE_SUPABASE_URL: " https://db.example.test ",
      VITE_SUPABASE_PUBLISHABLE_KEY: " publishable ",
      VITE_SUPABASE_ANON_KEY: "legacy-anon",
      VITE_SUPABASE_SERVICE_ROLE_KEY: "must-never-be-consumed",
    } as unknown as SupabaseBrowserEnv;

    expect(readSupabaseBrowserEnvironment(env)).toEqual({
      configured: true,
      url: "https://db.example.test",
      key: "publishable",
    });
    expect(JSON.stringify(readSupabaseBrowserEnvironment(env))).not.toContain(
      "must-never-be-consumed",
    );
  });

  it("keeps Ops source isolated from main-app views and components", () => {
    const sources = import.meta.glob("../../src-ops/**/*.{ts,vue}", {
      eager: true,
      import: "default",
      query: "?raw",
    });
    const joined = Object.values(sources).join("\n");

    expect(joined).not.toMatch(/from\s+["']@\/(?:views|components)\//);
  });

  it("password login requires Ops access after Supabase authentication", async () => {
    mocks.signInWithPassword.mockResolvedValue({
      data: { session, user: session.user },
      error: null,
    });
    mocks.opsApi.mockResolvedValue({
      ok: true,
      data: { userId: session.user.id },
    });
    const auth = useOpsAuthStore();

    await expect(auth.login("ops@example.test", "password-1")).resolves.toEqual(
      { ok: true },
    );

    expect(mocks.signInWithPassword).toHaveBeenCalledWith({
      email: "ops@example.test",
      password: "password-1",
    });
    expect(mocks.opsApi).toHaveBeenCalledWith(
      { action: "access" },
      session.access_token,
    );
    expect(auth.isAuthenticated).toBe(true);
    expect(auth.isAuthorized).toBe(true);
  });

  it("fails closed and clears the session when access is forbidden", async () => {
    mocks.signInWithPassword.mockResolvedValue({
      data: { session, user: session.user },
      error: null,
    });
    mocks.opsApi.mockResolvedValue({ ok: false, code: "FORBIDDEN" });
    const auth = useOpsAuthStore();

    await expect(
      auth.login("normal@example.test", "password-1"),
    ).resolves.toEqual({ ok: false, code: "FORBIDDEN" });

    expect(mocks.signOut).toHaveBeenCalledTimes(1);
    expect(auth.isAuthenticated).toBe(false);
    expect(auth.isAuthorized).toBe(false);
  });

  it("initialize gates an existing Ops session before marking it authorized", async () => {
    mocks.getSession.mockResolvedValue({
      data: { session },
      error: null,
    });
    mocks.opsApi.mockResolvedValue({
      ok: true,
      data: { userId: session.user.id },
    });
    const auth = useOpsAuthStore();

    await auth.initialize();

    expect(mocks.opsApi).toHaveBeenCalledWith(
      { action: "access" },
      session.access_token,
    );
    expect(auth.initialized).toBe(true);
    expect(auth.isAuthorized).toBe(true);
  });

  it("logout clears Ops authorization and Supabase session", async () => {
    mocks.signInWithPassword.mockResolvedValue({
      data: { session, user: session.user },
      error: null,
    });
    mocks.opsApi.mockResolvedValue({
      ok: true,
      data: { userId: session.user.id },
    });
    const auth = useOpsAuthStore();
    await auth.login("ops@example.test", "password-1");

    await auth.logout();

    expect(mocks.signOut).toHaveBeenCalled();
    expect(auth.isAuthenticated).toBe(false);
    expect(auth.isAuthorized).toBe(false);
  });
});
