import { describe, expect, it, vi } from "vitest";

import { createRepository } from "@/services/repository";

describe("entitlement repository", () => {
  it("reads the current account entitlement through its self-only RPC", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        ok: true,
        plan: "free",
        state: "expired",
        startsAt: "2026-01-01T00:00:00.000Z",
        expiresAt: "2026-09-30T00:00:00.000Z",
        version: 3,
      },
      error: null,
    });
    const repository = createRepository({ rpc } as never);

    await expect(repository.getMyAccountEntitlement()).resolves.toEqual({
      plan: "free",
      state: "expired",
      startsAt: "2026-01-01T00:00:00.000Z",
      expiresAt: "2026-09-30T00:00:00.000Z",
      version: 3,
    });
    expect(rpc).toHaveBeenCalledWith("get_my_account_entitlement");
  });

  it("reads the effective project entitlement through the stable RPC name", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        ok: true,
        projectId: "project-1",
        plan: "pro",
        state: "grace",
        source: "grace",
        graceExpiresAt: "2026-10-08T00:00:00.000Z",
      },
      error: null,
    });
    const repository = createRepository({ rpc } as never);

    await expect(
      repository.getProjectEntitlement("project-1"),
    ).resolves.toEqual({
      projectId: "project-1",
      plan: "pro",
      state: "grace",
      source: "grace",
      graceExpiresAt: "2026-10-08T00:00:00.000Z",
    });
    expect(rpc).toHaveBeenCalledWith("get_project_entitlement", {
      p_project_id: "project-1",
    });
  });

  it("rejects the legacy project entitlement payload", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        ok: true,
        projectId: "project-1",
        plan: "early_access_pro",
        active: true,
        status: "active",
        startsAt: "2026-09-30T00:00:00.000Z",
        expiresAt: null,
        version: 2,
      },
      error: null,
    });
    const repository = createRepository({ rpc } as never);

    await expect(repository.getProjectEntitlement("project-1")).rejects.toThrow(
      "Invalid project entitlement payload",
    );
  });

  it("rejects malformed account plan/state combinations", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        ok: true,
        plan: "pro",
        state: "expired",
        startsAt: "2026-01-01T00:00:00.000Z",
        expiresAt: "2026-09-30T00:00:00.000Z",
        version: 3,
      },
      error: null,
    });
    const repository = createRepository({ rpc } as never);

    await expect(repository.getMyAccountEntitlement()).rejects.toThrow(
      "Invalid account entitlement payload",
    );
  });
});
