import { describe, expect, it } from "vitest";
import { renderCalendarFeed } from "../../supabase/functions/_shared/calendar-ics";

/** Independent RFC 5545 subset reader used to validate emitted wire format. */
function parseIcalendar(source: string) {
  if (!source.endsWith("\r\n")) throw new Error("Missing terminal CRLF");
  const physical = source.split("\r\n");
  physical.pop();
  const unfolded: string[] = [];
  const encoder = new TextEncoder();
  for (const line of physical) {
    if (encoder.encode(line).byteLength > 75)
      throw new Error("Line exceeds 75 octets");
    if (/^[ \t]/.test(line)) {
      if (unfolded.length === 0)
        throw new Error("Invalid folding continuation");
      unfolded[unfolded.length - 1] += line.slice(1);
    } else {
      unfolded.push(line);
    }
  }
  if (
    unfolded.shift() !== "BEGIN:VCALENDAR" ||
    unfolded.pop() !== "END:VCALENDAR"
  ) {
    throw new Error("Missing VCALENDAR envelope");
  }
  const header = new Map<string, string>();
  const events: Map<string, string>[] = [];
  let active: Map<string, string> | null = null;
  for (const line of unfolded) {
    if (line === "BEGIN:VEVENT") {
      if (active) throw new Error("Nested VEVENT");
      active = new Map();
      continue;
    }
    if (line === "END:VEVENT") {
      if (!active) throw new Error("VEVENT not open");
      for (const required of [
        "UID",
        "DTSTAMP",
        "DTSTART",
        "DTEND",
        "SUMMARY",
      ]) {
        if (!active.has(required)) throw new Error("Missing VEVENT property");
      }
      for (const dateKey of ["DTSTAMP", "DTSTART", "DTEND"]) {
        if (!/^\d{8}T\d{6}Z$/.test(active.get(dateKey)!)) {
          throw new Error("Non-UTC date time");
        }
      }
      events.push(active);
      active = null;
      continue;
    }
    const offset = line.indexOf(":");
    if (offset < 1) throw new Error("Invalid property");
    const name = line.slice(0, offset);
    const value = line.slice(offset + 1);
    const target = active ?? header;
    if (target.has(name)) throw new Error("Duplicate property");
    target.set(name, value);
  }
  if (active || header.get("VERSION") !== "2.0" || !header.has("PRODID")) {
    throw new Error("Invalid calendar headers");
  }
  return { header, events };
}

describe("Pro Phase 2 E: independent RFC 5545 reader", () => {
  it("parses a folded two-event Chinese/unicode calendar as structured events", () => {
    const value = renderCalendarFeed(
      {
        ok: true,
        showTitles: true,
        truncated: false,
        events: [
          {
            uid: "1".repeat(64),
            deadline: "2026-12-31T23:50:00Z",
            title: "甲,乙;丙\\丁\n测试😀".repeat(15),
          },
          {
            uid: "2".repeat(64),
            deadline: "2027-01-01T00:01:00Z",
            title: "第二项",
          },
        ],
      },
      new Date("2026-10-06T00:00:00Z"),
    );
    const parsed = parseIcalendar(value);
    expect(parsed.events).toHaveLength(2);
    expect(parsed.events[0]?.get("DTSTART")).toBe("20261231T235000Z");
    expect(parsed.events[0]?.get("DTEND")).toBe("20270101T000500Z");
    expect(parsed.events[0]?.get("SUMMARY")).toContain("\\,");
    expect(parsed.events[0]?.get("SUMMARY")).toContain("\\;");
    expect(parsed.events[0]?.get("SUMMARY")).toContain("\\n");
    expect(parsed.events[1]?.get("SUMMARY")).toBe("第二项");
    expect(parsed.events[0]?.get("UID")).not.toBe(parsed.events[1]?.get("UID"));
  });
  it("parses an empty calendar and rejects incorrectly folded data", () => {
    const empty = renderCalendarFeed({
      ok: true,
      events: [],
      showTitles: false,
      truncated: false,
    });
    expect(parseIcalendar(empty).events).toHaveLength(0);
    expect(() => parseIcalendar(empty.replace("\r\n", "\n"))).toThrow();
  });
});
