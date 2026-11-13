import { describe, expect, it } from "vitest";
import {
  escapeCalendarText,
  foldCalendarLine,
  renderCalendarFeed,
  utcCalendarDate,
} from "../../supabase/functions/_shared/calendar-ics";

const UID = "a".repeat(64);
const event = (
  title: string | null,
  deadline = "2026-12-31T23:58:00.000Z",
) => ({
  uid: UID,
  deadline,
  title,
});

describe("Pro Phase 2 E: RFC 5545 calendar serialization", () => {
  it("emits a complete UTC calendar and a 15-minute event across year boundaries", () => {
    const value = renderCalendarFeed(
      { ok: true, events: [event("测试")], showTitles: true, truncated: false },
      new Date("2026-12-01T00:00:00.000Z"),
    );
    expect(value).toContain("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n");
    expect(value).toContain("DTSTAMP:20261201T000000Z");
    expect(value).toContain("DTSTART:20261231T235800Z");
    expect(value).toContain("DTEND:20270101T001300Z");
    expect(value.replace(/\r\n /g, "")).toContain(
      "UID:" + UID + "@calendar.xiaozhuzuoye",
    );
    expect(value).toContain("SUMMARY:测试");
    expect(value.endsWith("END:VCALENDAR\r\n")).toBe(true);
    expect(value).not.toContain("\n\n");
  });
  it("redacts titles by default, never includes other task/member metadata", () => {
    const value = renderCalendarFeed({
      ok: true,
      events: [event("私密\n危险")],
      showTitles: false,
      truncated: false,
    });
    expect(value).toContain("SUMMARY:小猪作业任务截止");
    expect(value).not.toContain("私密");
    expect(value).not.toContain("DESCRIPTION:");
    expect(value).not.toContain("ATTACH:");
  });
  it("escapes newlines, commas, semicolons, slashes and control characters", () => {
    expect(escapeCalendarText("甲\\乙,丙;丁\r\nBEGIN:VALARM\u0001")).toBe(
      "甲\\\\乙\\,丙\\;丁\\nBEGIN:VALARM",
    );
  });
  it("folds at 75 UTF-8 octets without splitting Unicode code points", () => {
    const folded = foldCalendarLine("SUMMARY:" + "测试😀".repeat(80));
    for (const physicalLine of folded.split("\r\n")) {
      expect(new TextEncoder().encode(physicalLine).length).toBeLessThanOrEqual(
        75,
      );
    }
    expect(folded.replace(/\r\n /g, "")).toBe("SUMMARY:" + "测试😀".repeat(80));
  });
  it("rejects malformed dates, UIDs and unbounded data", () => {
    expect(() => utcCalendarDate(new Date(NaN))).toThrow();
    expect(() =>
      renderCalendarFeed({
        ok: true,
        events: [event(null, "invalid")],
        showTitles: false,
        truncated: false,
      }),
    ).toThrow();
    expect(() =>
      renderCalendarFeed({
        ok: true,
        events: [{ ...event(null), uid: "unsafe" }],
        showTitles: false,
        truncated: false,
      }),
    ).toThrow();
    expect(() =>
      renderCalendarFeed({
        ok: true,
        events: Array.from({ length: 501 }, () => event(null)),
        showTitles: false,
        truncated: true,
      }),
    ).toThrow();
  });
  it("marks a bounded truncated feed; empty feeds remain valid", () => {
    const empty = renderCalendarFeed({
      ok: true,
      events: [],
      showTitles: false,
      truncated: false,
    });
    expect(empty).not.toContain("BEGIN:VEVENT");
    const truncated = renderCalendarFeed({
      ok: true,
      events: [event(null)],
      showTitles: false,
      truncated: true,
    });
    expect(truncated).toContain("X-XIAOZHUWORK-TRUNCATED:TRUE");
  });
});
