import { describe, expect, it } from "vitest";

import { buildProjectInviteUrl } from "@/platform/project-invite-url";

describe("project invitation links", () => {
  const token = "invite/qa?token";

  it("uses the public backend origin rather than the Capacitor localhost origin", () => {
    expect(
      buildProjectInviteUrl(token, {
        isNative: true,
        webOrigin: "https://localhost",
        backendUrl: "https://xiaozhuwork.com",
      }),
    ).toBe("https://xiaozhuwork.com/invite/invite%2Fqa%3Ftoken");
  });

  it("uses the active website origin in browsers and preview deployments", () => {
    expect(
      buildProjectInviteUrl(token, {
        isNative: false,
        webOrigin: "https://preview.example.test",
        backendUrl: "https://xiaozhuwork.com",
      }),
    ).toBe("https://preview.example.test/invite/invite%2Fqa%3Ftoken");
  });

  it("strips backend URL paths but preserves its HTTPS origin", () => {
    expect(
      buildProjectInviteUrl("abc", {
        isNative: true,
        webOrigin: "https://localhost",
        backendUrl: "https://xiaozhuwork.com/rest/v1",
      }),
    ).toBe("https://xiaozhuwork.com/invite/abc");
  });

  it("refuses to generate localhost or HTTP native invitation links", () => {
    for (const backendUrl of [
      "https://localhost",
      "http://xiaozhuwork.com",
      "http://127.0.0.1:54321",
    ]) {
      expect(() =>
        buildProjectInviteUrl("abc", {
          isNative: true,
          webOrigin: "https://localhost",
          backendUrl,
        }),
      ).toThrow();
    }
  });
});
