import { describe, expect, it } from "vitest";

import {
  containsSensitiveTelemetryValue,
  normalizeRouteTemplate,
  sanitizeUrl,
} from "@shared/telemetry";

describe("telemetry route sanitization", () => {
  it.each([
    ["login", "/login", "登录"],
    ["register", "/register", "注册"],
    ["forgot-password", "/forgot-password", "找回密码"],
    ["projects", "/projects", "项目列表"],
    ["project-overview", "/projects/:projectId", "项目概览"],
    ["task-detail", "/projects/:projectId/tasks/:taskId", "任务详情"],
    ["file-detail", "/projects/:projectId/files/:fileId", "文件详情"],
    [
      "review-detail",
      "/projects/:projectId/reviews/:reviewRoundId",
      "验收详情",
    ],
    ["account-settings", "/account/settings", "账号设置"],
    ["upgrade", "/upgrade", "方案与升级"],
  ])("maps %s to a fixed telemetry template", (name, url, title) => {
    expect(
      normalizeRouteTemplate({
        name,
        path: "/raw/" + crypto.randomUUID(),
      }),
    ).toEqual({ url, title });
  });

  it("fails closed for an unknown route instead of forwarding its raw path", () => {
    expect(
      normalizeRouteTemplate({
        name: "future-secret-route",
        path: "/projects/" + crypto.randomUUID() + "/private",
      }),
    ).toEqual({ url: "/other", title: "其他页面" });
  });

  it("strips query/hash and redacts UUID path segments", () => {
    const projectId = "123e4567-e89b-12d3-a456-426614174000";
    const taskId = "123e4567-e89b-12d3-a456-426614174001";

    expect(
      sanitizeUrl(
        "https://www.xiaozhuwork.com/projects/" +
          projectId +
          "/tasks/" +
          taskId +
          "?token=secret#body",
      ),
    ).toBe("/projects/:id/tasks/:id");
  });

  it.each([
    "student@example.edu",
    "123e4567-e89b-12d3-a456-426614174000",
    "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature",
    "token=super-secret",
    "authorization: Bearer abc.def.ghi",
  ])("recognizes sensitive telemetry values: %s", (value) => {
    expect(containsSensitiveTelemetryValue(value)).toBe(true);
  });

  it.each([
    "/projects/:projectId/tasks/:taskId",
    "项目任务",
    "desktop-chromium",
    "campaign-autumn",
  ])("allows bounded non-sensitive telemetry values: %s", (value) => {
    expect(containsSensitiveTelemetryValue(value)).toBe(false);
  });
});
