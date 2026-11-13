import type { User } from "@supabase/supabase-js";
import { createPinia, setActivePinia } from "pinia";
import { createMemoryHistory } from "vue-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { getAccountLifecycleStatus } from "@/features/account-lifecycle/repository";
import { createAppRouter } from "@/router";
import { useAuthStore } from "@/stores/auth";

vi.mock("@/features/account-lifecycle/repository", () => ({
  getAccountLifecycleStatus: vi.fn(),
}));

function signedIn(profile: Record<string, unknown> | null = null) {
  const auth = useAuthStore();
  auth.$patch({
    initialized: true,
    user: { id: "test-member", email: "member@example.test" } as User,
    profile,
  });
}

describe("account deletion route safety gate", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.stubGlobal("scrollTo", vi.fn());
    vi.mocked(getAccountLifecycleStatus).mockReset();
  });
  afterEach(() => vi.unstubAllEnvs());

  it("keeps incomplete/unreleased account deletion UI unavailable by default", async () => {
    vi.stubEnv("VITE_ACCOUNT_DELETION_ENABLED", "false");
    signedIn({ display_name: "member" });
    const router = createAppRouter(createMemoryHistory());
    await router.push("/account/deletion");
    expect(router.currentRoute.value.name).toBe("account-settings");
    expect(getAccountLifecycleStatus).not.toHaveBeenCalled();
  }, 20_000);

  it("preserves cancellation path for an RLS-blocked pending account", async () => {
    vi.stubEnv("VITE_ACCOUNT_DELETION_ENABLED", "true");
    vi.mocked(getAccountLifecycleStatus).mockResolvedValue({
      state: "pending",
      version: 1,
      cancelUntil: "2026-12-01T00:00:00Z",
    });
    signedIn(null);
    const router = createAppRouter(createMemoryHistory());
    await router.push("/projects");
    expect(router.currentRoute.value.name).toBe("account-deletion");
  });

  it("uses normal nickname completion for a non-deleting account", async () => {
    vi.stubEnv("VITE_ACCOUNT_DELETION_ENABLED", "true");
    vi.mocked(getAccountLifecycleStatus).mockResolvedValue({
      state: "active",
      version: 0,
    });
    signedIn(null);
    const router = createAppRouter(createMemoryHistory());
    await router.push("/projects");
    expect(router.currentRoute.value.name).toBe("account-settings");
    expect(router.currentRoute.value.query.mode).toBe("complete");
  });
});
