import { describe, expect, it, vi } from "vitest";

import {
  createProjectPermissionsService,
  decodePermissionSnapshot,
  delegationAssigned,
  delegationEffective,
  permissionErrorMessage,
  ProjectPermissionError,
} from "@/services/project-permissions";

const delegation = {
  delegationId: "d-1",
  membershipId: "m-1",
  templateCode: "invitation_coordinator",
  grantedAt: "2026-10-07T00:00:00Z",
  revokedAt: null,
  version: 1,
  membershipVersion: 3,
  effective: false,
};

function response(delegations: unknown[] = [delegation]) {
  return {
    ok: true,
    data: {
      schemaVersion: 1,
      projectId: "p-1",
      viewerRole: "member",
      capability: { released: false, entitled: false, effective: false },
      delegations,
    },
  };
}

describe("D project permissions service", () => {
  it("decodes assigned but suspended grant without manufacturing authority", () => {
    const snapshot = decodePermissionSnapshot(response());
    expect(delegationAssigned(snapshot, "m-1", "invitation_coordinator")).toBe(
      true,
    );
    expect(delegationEffective(snapshot, "m-1", "invitation_coordinator")).toBe(
      false,
    );
    expect(
      delegationAssigned(snapshot, "other", "invitation_coordinator"),
    ).toBe(false);
    expect(delegationAssigned(snapshot, "m-1", "intake_reviewer")).toBe(false);
  });

  it("treats a revoked historical row as unassigned", () => {
    const snapshot = decodePermissionSnapshot(
      response([{ ...delegation, revokedAt: "2026-10-07T01:00:00Z" }]),
    );
    expect(delegationAssigned(snapshot, "m-1", "invitation_coordinator")).toBe(
      false,
    );
  });

  it("rejects malformed templates rather than treating them as permissions", () => {
    expect(() =>
      decodePermissionSnapshot(
        response([{ ...delegation, templateCode: "superuser" }]),
      ),
    ).toThrow(ProjectPermissionError);
  });

  it("sends exact frozen public RPC arguments", async () => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: response([]), error: null })
      .mockResolvedValueOnce({
        data: {
          ok: true,
          data: {
            projectId: "p-1",
            membershipId: "m-1",
            templateCode: "intake_reviewer",
            enabled: true,
            changed: true,
            membershipVersion: 4,
            effective: true,
          },
        },
        error: null,
      });
    const service = createProjectPermissionsService({ rpc });
    expect((await service.get("p-1")).delegations).toEqual([]);
    const result = await service.set({
      projectId: "p-1",
      membershipId: "m-1",
      templateCode: "intake_reviewer",
      enabled: true,
      expectedVersion: 3,
      requestId: "r-1",
    });
    expect(result.membershipVersion).toBe(4);
    expect(rpc).toHaveBeenNthCalledWith(
      2,
      "cmd_set_project_permission_delegation",
      {
        p_project_id: "p-1",
        p_membership_id: "m-1",
        p_template_code: "intake_reviewer",
        p_enabled: true,
        p_expected_version: 3,
        p_request_id: "r-1",
      },
    );
  });

  it("surfaces stale and reused request ids without silently retrying", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { ok: false, code: "STALE_VERSION", currentVersion: 5 },
      error: null,
    });
    const service = createProjectPermissionsService({ rpc });
    await expect(service.get("p-1")).rejects.toMatchObject({
      code: "STALE_VERSION",
      currentVersion: 5,
    });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(
      permissionErrorMessage(
        new ProjectPermissionError("IDEMPOTENCY_KEY_REUSED"),
      ),
    ).toContain("其他内容");
  });

  it("does not infer access from a transport error", async () => {
    const service = createProjectPermissionsService({
      rpc: vi
        .fn()
        .mockResolvedValue({ data: null, error: { message: "failed" } }),
    });
    await expect(service.get("p-1")).rejects.toMatchObject({
      code: "TRANSPORT_FAILURE",
    });
  });
});
