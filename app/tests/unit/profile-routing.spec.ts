import type { User } from "@supabase/supabase-js";
import { createPinia, setActivePinia } from "pinia";
import { createMemoryHistory } from "vue-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { createAppRouter } from "@/router";
import { useAuthStore } from "@/stores/auth";
import type { ProfileRow } from "@/types/ui";

function user(id = "user-1") {
  return { id, email: "user@example.com" } as User;
}

function profile(displayName: string | null) {
  return {
    id: "user-1",
    display_name: displayName,
    real_name: null,
    student_number: null,
    created_at: "2026-10-01T00:00:00Z",
    updated_at: "2026-10-01T00:00:00Z",
  } as ProfileRow;
}

describe("nickname completion routing", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });
  vi.stubGlobal("scrollTo", vi.fn());

  it("preserves a logged-out target through login", async () => {
    const auth = useAuthStore();
    auth.$patch({ initialized: true, user: null, profile: null });
    const router = createAppRouter(createMemoryHistory());

    await router.push("/projects/project-1/todos");

    expect(router.currentRoute.value.name).toBe("login");
    expect(router.currentRoute.value.query.return).toBe(
      "/projects/project-1/todos",
    );
  });

  it("does not show onboarding when display_name is present", async () => {
    const auth = useAuthStore();
    auth.$patch({
      initialized: true,
      user: user(),
      profile: profile("小林"),
    });
    const router = createAppRouter(createMemoryHistory());

    await router.push("/projects");

    expect(router.currentRoute.value.fullPath).toBe("/projects");
  }, 15_000);

  it("routes an authenticated invite through nickname completion and back", async () => {
    const auth = useAuthStore();
    auth.$patch({
      initialized: true,
      user: user(),
      profile: profile("   "),
    });
    const router = createAppRouter(createMemoryHistory());

    await router.push("/invite/token-123");

    expect(router.currentRoute.value.name).toBe("account-settings");
    expect(router.currentRoute.value.query.mode).toBe("complete");
    expect(router.currentRoute.value.query.return).toBe("/invite/token-123");

    auth.$patch({ profile: profile("小林") });
    await router.replace("/invite/token-123");

    expect(router.currentRoute.value.fullPath).toBe("/invite/token-123");
  });

  it("protects /upgrade with the existing auth guard and preserves the return path", async () => {
    const auth = useAuthStore();
    auth.$patch({ initialized: true, user: null, profile: null });
    const router = createAppRouter(createMemoryHistory());

    await router.push("/upgrade");

    expect(router.currentRoute.value.name).toBe("login");
    expect(router.currentRoute.value.query.return).toBe("/upgrade");
  });

  it("allows a complete authenticated account to open /upgrade", async () => {
    const auth = useAuthStore();
    auth.$patch({
      initialized: true,
      user: user(),
      profile: profile("小林"),
    });
    const router = createAppRouter(createMemoryHistory());

    await router.push("/upgrade");

    expect(router.currentRoute.value.name).toBe("upgrade");
    expect(router.currentRoute.value.fullPath).toBe("/upgrade");
  });

  it("routes an incomplete profile through completion before /upgrade", async () => {
    const auth = useAuthStore();
    auth.$patch({
      initialized: true,
      user: user(),
      profile: profile(""),
    });
    const router = createAppRouter(createMemoryHistory());

    await router.push("/upgrade");

    expect(router.currentRoute.value.name).toBe("account-settings");
    expect(router.currentRoute.value.query.mode).toBe("complete");
    expect(router.currentRoute.value.query.return).toBe("/upgrade");
  });

  it("exposes the approved workspace todo route while keeping the legacy alias", () => {
    const router = createAppRouter(createMemoryHistory());
    expect(router.resolve("/workspace/todo").name).toBe("projects-todos");
    expect(router.resolve("/projects/todos").name).toBe("projects-todos");
  });
});
