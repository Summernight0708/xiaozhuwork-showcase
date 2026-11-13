import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  initializeUmami,
  createXiaozhuWorkUmamiBeforeSend,
  type UmamiTracker,
} from "@/services/telemetry/umami";

describe("Umami telemetry adapter", () => {
  beforeEach(() => {
    document.head.innerHTML = "";
    delete window.umami;
    delete window.xiaozhuworkUmamiBeforeSend;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("injects the reviewed v3.4.0 tracker attributes", () => {
    initializeUmami(
      { afterEach: vi.fn() },
      {
        hostUrl: "https://analytics.xiaozhuwork.com/",
        websiteId: "site-1",
      },
    );

    const script = document.head.querySelector("script");
    expect(script?.src).toBe("https://analytics.xiaozhuwork.com/script.js");
    expect(script?.dataset.websiteId).toBe("site-1");
    expect(script?.dataset.autoPageview).toBe("false");
    expect(script?.dataset.excludeSearch).toBe("true");
    expect(script?.dataset.excludeHash).toBe("true");
    expect(script?.dataset.doNotTrack).toBe("true");
    expect(script?.dataset.beforeSend).toBe("xiaozhuworkUmamiBeforeSend");
    expect(script?.dataset.distinctId).toBeUndefined();
  });

  it("sends one normalized pageview after router navigation", () => {
    let afterEach:
      | ((route: { name?: string | symbol | null; path?: string }) => void)
      | undefined;
    const track = vi.fn();
    window.umami = { track } satisfies UmamiTracker;

    initializeUmami(
      {
        afterEach: vi.fn((callback) => {
          afterEach = callback;
        }),
      },
      {
        hostUrl: "https://analytics.xiaozhuwork.com",
        websiteId: "site-1",
      },
    );

    afterEach?.({
      name: "task-detail",
      path:
        "/projects/123e4567-e89b-12d3-a456-426614174000/tasks/" +
        "123e4567-e89b-12d3-a456-426614174001?token=secret",
    });

    expect(track).toHaveBeenCalledOnce();
    expect(track).toHaveBeenCalledWith({
      website: "site-1",
      url: "/projects/:projectId/tasks/:taskId",
      title: "任务详情",
    });
  });

  it("fails closed to /other for an unknown route", () => {
    let afterEach:
      | ((route: { name?: string | symbol | null; path?: string }) => void)
      | undefined;
    const track = vi.fn();
    window.umami = { track } satisfies UmamiTracker;

    initializeUmami(
      {
        afterEach: vi.fn((callback) => {
          afterEach = callback;
        }),
      },
      {
        hostUrl: "https://analytics.xiaozhuwork.com",
        websiteId: "site-1",
      },
    );

    afterEach?.({
      name: "future-secret",
      path: "/projects/123e4567-e89b-12d3-a456-426614174000/private",
    });

    expect(track).toHaveBeenCalledWith({
      website: "site-1",
      url: "/other",
      title: "其他页面",
    });
  });

  it("cancels payloads containing UUID, email, query/hash or unknown fields", () => {
    const beforeSend = createXiaozhuWorkUmamiBeforeSend("site-1");

    expect(
      beforeSend("event", {
        website: "site-1",
        url: "/projects/:projectId",
        title: "项目概览",
        email: "student@example.edu",
      }),
    ).toBe(false);

    expect(
      beforeSend("event", {
        website: "site-1",
        url: "/projects/123e4567-e89b-12d3-a456-426614174000",
        title: "项目概览",
      }),
    ).toBe(false);

    expect(
      beforeSend("event", {
        website: "site-1",
        url: "/projects/:projectId?token=secret",
        title: "项目概览",
      }),
    ).toBe(false);
  });

  it("allows the configured Umami UUID while rejecting UUIDs elsewhere", () => {
    const website = "824afa58-eb12-4e9b-b52b-334045834357";
    const beforeSend = createXiaozhuWorkUmamiBeforeSend(website);
    const payload = {
      website,
      url: "/projects/:projectId/tasks/:taskId",
      title: "任务详情",
    };

    expect(beforeSend("event", payload)).toEqual(payload);
    expect(
      beforeSend("event", {
        ...payload,
        website: "123e4567-e89b-12d3-a456-426614174999",
      }),
    ).toBe(false);
    expect(
      beforeSend("event", {
        ...payload,
        title: "项目 123e4567-e89b-12d3-a456-426614174000",
      }),
    ).toBe(false);
    expect(beforeSend("identify", payload)).toBe(false);
  });

  it("does nothing when configuration is incomplete", () => {
    const afterEach = vi.fn();

    initializeUmami(
      { afterEach },
      {
        hostUrl: "",
        websiteId: "site-1",
      },
    );

    expect(document.head.querySelector("script")).toBeNull();
    expect(afterEach).not.toHaveBeenCalled();
  });
});
