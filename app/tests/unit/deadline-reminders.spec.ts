import { describe, expect, it } from "vitest";
import {
  DEFAULT_REMINDER_OFFSETS,
  displayReminderOffset,
  normalizeReminderOffsets,
} from "@/features/deadline-reminders/model";

describe("task reminder offsets", () => {
  it("defaults to 24h and 2h", () => {
    expect(DEFAULT_REMINDER_OFFSETS).toEqual([86_400, 7_200]);
  });
  it("sorts valid offsets in descending order", () => {
    expect(normalizeReminderOffsets([600, 7_200, 86_400])).toEqual([
      86_400, 7_200, 600,
    ]);
  });
  it("refuses duplicates", () => {
    expect(() => normalizeReminderOffsets([7_200, 7_200])).toThrow();
  });
  it.each([
    [[0]],
    [[299]],
    [[301]],
    [[1_209_660]],
    [[NaN]],
    [[Infinity]],
    [[10.5]],
    [[]],
  ])("refuses invalid range, granularity, or empty input %j", (value) =>
    expect(() => normalizeReminderOffsets(value)).toThrow(),
  );
  it("limits the number of personal nodes", () => {
    expect(() =>
      normalizeReminderOffsets([300, 360, 420, 480, 540, 600, 660]),
    ).toThrow();
  });
  it("formats offsets", () => {
    expect(displayReminderOffset(86_400)).toBe("1 天前");
    expect(displayReminderOffset(7_200)).toBe("2 小时前");
    expect(displayReminderOffset(600)).toBe("10 分钟前");
  });
});
