/**
 * Pure RFC 5545 serializer. It never receives private project/member metadata.
 * Octet folding counts UTF-8 bytes rather than JavaScript UTF-16 code units.
 */
export type CalendarEvent = {
  uid: string;
  deadline: string;
  title: string | null;
};
export type CalendarFeed = {
  ok: true;
  events: CalendarEvent[];
  showTitles: boolean;
  truncated: boolean;
};

const encoder = new TextEncoder();
const MAX_TITLE_CODEPOINTS = 240;
const MAX_EVENTS = 500;

export function escapeCalendarText(value: string): string {
  const bounded = Array.from(value.normalize("NFC"))
    .slice(0, MAX_TITLE_CODEPOINTS)
    .join("")
    // Explicitly strip ASCII control bytes, excluding CR/LF for newline escaping.
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "");
  return bounded
    .replace(/\\/g, "\\\\")
    .replace(/\r\n|\r|\n/g, "\\n")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,");
}

export function foldCalendarLine(line: string): string {
  const parts: string[] = [];
  let chunk = "";
  let length = 0;
  for (const codepoint of line) {
    const bytes = encoder.encode(codepoint).length;
    if (length + bytes > 75) {
      parts.push(chunk);
      chunk = " ";
      length = 1;
    }
    chunk += codepoint;
    length += bytes;
  }
  parts.push(chunk);
  return parts.join("\r\n");
}

export function utcCalendarDate(date: Date): string {
  if (!Number.isFinite(date.getTime()))
    throw new Error("Invalid calendar date");
  return date
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}Z$/, "Z");
}

export function renderCalendarFeed(
  input: CalendarFeed,
  stamp: Date = new Date(),
): string {
  if (
    !input.ok ||
    !Array.isArray(input.events) ||
    input.events.length > MAX_EVENTS
  ) {
    throw new Error("Invalid bounded calendar feed");
  }
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//XiaoZhuZuoYe//Pro Calendar Feed v1//ZH",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:小猪作业任务截止",
  ];
  if (input.truncated) lines.push("X-XIAOZHUWORK-TRUNCATED:TRUE");
  const dtstamp = utcCalendarDate(stamp);
  for (const event of input.events) {
    if (!/^[a-f0-9]{64}$/.test(event.uid)) throw new Error("Invalid UID");
    const start = new Date(event.deadline);
    if (!Number.isFinite(start.getTime())) throw new Error("Invalid deadline");
    lines.push(
      "BEGIN:VEVENT",
      `UID:${event.uid}@calendar.xiaozhuzuoye`,
      `DTSTAMP:${dtstamp}`,
      `DTSTART:${utcCalendarDate(start)}`,
      `DTEND:${utcCalendarDate(new Date(start.getTime() + 15 * 60_000))}`,
      `SUMMARY:${escapeCalendarText(input.showTitles && event.title ? event.title : "小猪作业任务截止")}`,
      "END:VEVENT",
    );
  }
  lines.push("END:VCALENDAR");
  return lines.map(foldCalendarLine).join("\r\n") + "\r\n";
}
