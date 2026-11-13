import { beforeEach, describe, expect, it, vi } from "vitest";

const mockRpc = vi.hoisted(() => vi.fn());
vi.mock("@/services/backend", () => ({
  getBackend: () => ({ client: { rpc: mockRpc } }),
}));
import {
  calendarSubscriptionUrl,
  createCalendarSubscription,
  listCalendarSubscriptions,
  revokeCalendarSubscription,
} from "@/services/calendar-subscriptions";

describe("Pro Phase 2 E: subscription service adapter", () => {
  beforeEach(() => mockRpc.mockReset());
  it("passes trusted project/version/request fields and title opt-in", async () => {
    mockRpc.mockResolvedValue({
      data: { ok: true, data: { id: "s", token: "f".repeat(64) } },
      error: null,
    });
    const result = await createCalendarSubscription(
      "project-1",
      8,
      false,
      "request-1",
    );
    expect(result.ok).toBe(true);
    expect(mockRpc).toHaveBeenCalledWith(
      "cmd_create_calendar_feed_subscription",
      {
        p_project_id: "project-1",
        p_expected_version: 8,
        p_request_id: "request-1",
        p_show_titles: false,
      },
    );
  });
  it("uses separate read and revoke RPCs without secret recovery", async () => {
    mockRpc.mockResolvedValue({
      data: { ok: true, data: { subscriptions: [], projectVersion: 9 } },
      error: null,
    });
    await listCalendarSubscriptions("project-1");
    expect(mockRpc).toHaveBeenCalledWith("get_project_calendar_subscriptions", {
      p_project_id: "project-1",
    });
    await revokeCalendarSubscription("project-1", "sub-1", 2, "req-2");
    expect(mockRpc).toHaveBeenCalledWith(
      "cmd_revoke_calendar_feed_subscription",
      {
        p_project_id: "project-1",
        p_subscription_id: "sub-1",
        p_expected_version: 2,
        p_request_id: "req-2",
      },
    );
  });
  it("fails closed and formats only safe HTTPS subscription URLs", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "secret internal details" },
    });
    expect(await listCalendarSubscriptions("x")).toEqual({
      ok: false,
      code: "SERVICE_UNAVAILABLE",
    });
    expect(
      calendarSubscriptionUrl("f".repeat(64), "https://calendar.example/"),
    ).toBe(
      "https://calendar.example/functions/v1/calendar-feed/" +
        "f".repeat(64) +
        ".ics",
    );
    expect(() =>
      calendarSubscriptionUrl("weak", "https://calendar.example"),
    ).toThrow();
    expect(() =>
      calendarSubscriptionUrl("f".repeat(64), "http://calendar.example"),
    ).toThrow();
  });
});
