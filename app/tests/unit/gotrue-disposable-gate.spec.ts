import { describe, expect, it } from "vitest";

import { verifyDisposableGoTrueSoftDelete } from "../../scripts/verify-gotrue-soft-delete.mjs";

describe("disposable GoTrue soft-delete execution gate", () => {
  it("rejects any test without an explicit isolated project ID", async () => {
    await expect(verifyDisposableGoTrueSoftDelete({})).rejects.toThrow(
      /dedicated disposable project ID/,
    );
  });

  it("rejects a real or ordinary XiaozhuWork project", async () => {
    await expect(
      verifyDisposableGoTrueSoftDelete({
        XIAOZHUWORK_AUTH_E2E_PROJECT_ID: "xiaozhuwork_g_isolated_20261010",
        XIAOZHUWORK_RUN_DISPOSABLE_AUTH_E2E:
          "YES_DELETE_ONLY_NEW_SYNTHETIC_ACCOUNT",
        XIAOZHUWORK_AUTH_E2E_ACK_DISPOSABLE: "xiaozhuwork_g_isolated_20261010",
      }),
    ).rejects.toThrow(/dedicated disposable project ID/);
  });

  it("requires separate acknowledgment even for a correctly named test project", async () => {
    await expect(
      verifyDisposableGoTrueSoftDelete({
        XIAOZHUWORK_AUTH_E2E_PROJECT_ID: "xiaozhuwork_f2_auth_e2e_synthetic01",
        XIAOZHUWORK_RUN_DISPOSABLE_AUTH_E2E:
          "YES_DELETE_ONLY_NEW_SYNTHETIC_ACCOUNT",
      }),
    ).rejects.toThrow(/explicit disposable approval/);
  });

  it("requires a matching local project config before any Auth connection", async () => {
    await expect(
      verifyDisposableGoTrueSoftDelete({
        XIAOZHUWORK_AUTH_E2E_PROJECT_ID: "xiaozhuwork_f2_auth_e2e_synthetic01",
        XIAOZHUWORK_RUN_DISPOSABLE_AUTH_E2E:
          "YES_DELETE_ONLY_NEW_SYNTHETIC_ACCOUNT",
        XIAOZHUWORK_AUTH_E2E_ACK_DISPOSABLE:
          "xiaozhuwork_f2_auth_e2e_synthetic01",
        XIAOZHUWORK_AUTH_E2E_WORKDIR: "/no/such/local-project",
      }),
    ).rejects.toThrow();
  });
});
