import { createMemoryHistory } from "vue-router";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/stores/auth", () => ({
  useAuthStore: () => ({
    initialize: vi.fn().mockResolvedValue(undefined),
    isAuthenticated: false,
    profile: null,
  }),
}));

vi.mock("@/features/account-lifecycle/repository", () => ({
  getAccountLifecycleStatus: vi.fn(),
}));

import { createAppRouter } from "@/router";

describe("public auth routes", () => {
  it.each([
    ["login", "/login"],
    ["register", "/register"],
    ["forgot-password", "/forgot-password"],
  ])("marks %s as public bare entry", (name, path) => {
    const router = createAppRouter(createMemoryHistory());
    const route = router.getRoutes().find((item) => item.name === name);

    expect(route?.path).toBe(path);
    expect(route?.meta.public).toBe(true);
    expect(route?.meta.bare).toBe(true);
  });
});
