import { beforeEach, describe, expect, it, vi } from "vitest";

const setUser = vi.hoisted(() => vi.fn());

vi.mock("@sentry/vue", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@sentry/vue")>();
  return {
    ...actual,
    setUser,
  };
});

import {
  sanitizeSentryBreadcrumb,
  sanitizeSentryEvent,
  syncSentryUser,
} from "@/services/telemetry/sentry";

describe("Sentry privacy boundary", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("normalizes request URLs and removes query/hash, body and sensitive headers", () => {
    const event = sanitizeSentryEvent({
      request: {
        url:
          "https://www.xiaozhuwork.com/projects/" +
          "123e4567-e89b-12d3-a456-426614174000/tasks/" +
          "123e4567-e89b-12d3-a456-426614174001?token=secret#otp",
        method: "POST",
        data: { email: "student@example.edu", otp: "123456" },
        headers: {
          Authorization: "Bearer secret",
          Cookie: "session=secret",
          Accept: "application/json",
        },
      },
      user: {
        id: "user-1",
        email: "student@example.edu",
        username: "Student",
        ip_address: "203.0.113.1",
      },
      extra: {
        projectName: "秘密课程项目",
      },
    });

    expect(event?.request?.url).toBe("/projects/:projectId/tasks/:taskId");
    expect(event?.request?.data).toBeUndefined();
    expect(event?.request?.headers).toEqual({
      Accept: "application/json",
    });
    expect(event?.user).toEqual({ id: "user-1" });
    expect(event?.extra).toBeUndefined();
  });

  it("drops UI/input/console breadcrumbs that can contain user content", () => {
    expect(
      sanitizeSentryBreadcrumb({
        category: "ui.click",
        message: "打开项目：秘密课程项目",
      }),
    ).toBeNull();
    expect(
      sanitizeSentryBreadcrumb({
        category: "ui.input",
        message: "student@example.edu",
      }),
    ).toBeNull();
    expect(
      sanitizeSentryBreadcrumb({
        category: "console",
        message: "OTP 123456",
      }),
    ).toBeNull();
  });

  it("sanitizes navigation and fetch breadcrumbs to route templates", () => {
    const projectId = "123e4567-e89b-12d3-a456-426614174000";
    const taskId = "123e4567-e89b-12d3-a456-426614174001";

    expect(
      sanitizeSentryBreadcrumb({
        category: "navigation",
        data: {
          from: "/projects",
          to: "/projects/" + projectId + "/tasks/" + taskId + "?token=secret",
        },
      }),
    ).toEqual({
      category: "navigation",
      data: {
        from: "/projects",
        to: "/projects/:projectId/tasks/:taskId",
      },
    });

    expect(
      sanitizeSentryBreadcrumb({
        category: "fetch",
        data: {
          method: "GET",
          status_code: 200,
          url:
            "https://api.example.test/projects/" +
            projectId +
            "?email=student@example.edu",
          request_body: "private body",
        },
      }),
    ).toEqual({
      category: "fetch",
      data: {
        method: "GET",
        status_code: 200,
        url: "/projects/:projectId",
      },
    });
  });

  it("removes dynamic browser titles and sensitive breadcrumbs from events", () => {
    const event = sanitizeSentryEvent({
      transaction: "秘密课程项目 - 任务详情",
      breadcrumbs: [
        {
          category: "ui.click",
          message: "秘密课程项目",
        },
        {
          category: "navigation",
          data: {
            to: "/projects/123e4567-e89b-12d3-a456-426614174000?email=student@example.edu",
          },
        },
      ],
    });

    expect(event?.transaction).toBeUndefined();
    expect(event?.breadcrumbs).toEqual([
      {
        category: "navigation",
        data: { to: "/projects/:projectId" },
      },
    ]);
  });

  it("redacts sensitive top-level and exception messages", () => {
    const event = sanitizeSentryEvent({
      message: "student@example.edu token=secret otp=123456",
      exception: {
        values: [
          {
            type: "Error",
            value:
              "Recovery failed for student@example.edu token=secret otp=123456",
          },
        ],
      },
    });

    expect(event?.message).toBe("[redacted sensitive message]");
    expect(event?.exception?.values?.[0]?.value).toBe(
      "[redacted sensitive message]",
    );
    expect(JSON.stringify(event)).not.toContain("student@example.edu");
    expect(JSON.stringify(event)).not.toContain("token=secret");
    expect(JSON.stringify(event)).not.toContain("123456");
  });

  it("sets only pseudonymous UUID and clears it on logout", () => {
    syncSentryUser("user-1");
    expect(setUser).toHaveBeenLastCalledWith({ id: "user-1" });

    syncSentryUser(null);
    expect(setUser).toHaveBeenLastCalledWith(null);
  });
});
