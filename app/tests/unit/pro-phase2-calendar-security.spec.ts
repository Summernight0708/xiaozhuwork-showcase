import { describe, expect, it, vi } from "vitest";
import { handleCalendarFeedRequest } from "../../supabase/functions/calendar-feed/index";

const token = "a".repeat(64);
const url = `https://calendar.example/functions/v1/calendar-feed/${token}.ics`;
const event = {
  uid: "c".repeat(64),
  deadline: "2026-12-31T23:58:00+00:00",
  title: "机密任务",
};
const good = { ok: true, events: [event], showTitles: false, truncated: false };

function setup(body: unknown = good, status = 200) {
  const fetcher = vi.fn(
    async () => new Response(JSON.stringify(body), { status }),
  );
  const env = (key: string) =>
    ({
      SUPABASE_URL: "https://db.example",
      SUPABASE_SERVICE_ROLE_KEY: "test-service-only",
      CALENDAR_FEED_ENFORCE_HTTPS: "true",
    })[key];
  return {
    fetcher,
    env,
    allowRequest: () => true,
    now: () => new Date("2026-10-06T00:00:00Z"),
  };
}

describe("Pro Phase 2 E: anonymous calendar feed security boundary", () => {
  it("allows token-only GET without user JWT, returns safe ICS and never echoes token", async () => {
    const deps = setup();
    const response = await handleCalendarFeedRequest(new Request(url), deps);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(response.headers.get("content-type")).toContain("text/calendar");
    const content = await response.text();
    expect(content).toContain("BEGIN:VCALENDAR");
    expect(content).not.toContain("机密任务");
    expect(content).not.toContain(token);
    expect(deps.fetcher).toHaveBeenCalledOnce();
    const [, init] = deps.fetcher.mock.calls[0] as unknown as [
      unknown,
      RequestInit,
    ];
    expect(String(init.body)).toContain(token);
    expect(init.headers).toMatchObject({
      authorization: "Bearer test-service-only",
    });
  });
  it.each([
    "abc",
    "f".repeat(65),
    "f".repeat(63),
    "A".repeat(64),
    "f".repeat(64) + "/other",
  ])(
    "rejects malformed tokens without hitting the database: %s",
    async (bad) => {
      const deps = setup();
      const response = await handleCalendarFeedRequest(
        new Request(
          `https://calendar.example/functions/v1/calendar-feed/${bad}.ics`,
        ),
        deps,
      );
      expect(response.status).toBe(404);
      expect(deps.fetcher).not.toHaveBeenCalled();
    },
  );
  it("uses the same empty 404 for missing/revoked/expired and does not expose project state", async () => {
    for (const payload of [
      null,
      {},
      { ok: false, code: "CAPABILITY_REQUIRES_PRO" },
    ]) {
      const response = await handleCalendarFeedRequest(
        new Request(url),
        setup(payload),
      );
      expect(response.status).toBe(404);
      expect(await response.text()).toBe("");
    }
  });
  it("rejects method abuse, query tokens, plaintext and throttled requests", async () => {
    expect(
      (
        await handleCalendarFeedRequest(
          new Request(url, { method: "POST" }),
          setup(),
        )
      ).status,
    ).toBe(405);
    expect(
      (
        await handleCalendarFeedRequest(
          new Request(url + "?token=abc"),
          setup(),
        )
      ).status,
    ).toBe(404);
    expect(
      (
        await handleCalendarFeedRequest(
          new Request(url.replace("https", "http")),
          setup(),
        )
      ).status,
    ).toBe(404);
    expect(
      (
        await handleCalendarFeedRequest(new Request(url), {
          ...setup(),
          allowRequest: () => false,
        })
      ).status,
    ).toBe(429);
  });
  it("does not leak Service Role credentials on upstream failure", async () => {
    const deps = setup(null, 500);
    const response = await handleCalendarFeedRequest(new Request(url), deps);
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("");
    const error = await handleCalendarFeedRequest(new Request(url), {
      ...deps,
      fetcher: vi.fn(async () => {
        throw Error("test-service-only");
      }),
    });
    expect(error.status).toBe(404);
    expect(await error.text()).toBe("");
  });
});
