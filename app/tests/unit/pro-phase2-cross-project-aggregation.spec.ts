import { describe, expect, it } from "vitest";
import {
  aggregateProjectAnalytics,
  ContractError,
  utcDays,
} from "../../supabase/functions/_shared/cross-project-aggregation";

const id = (n: number) =>
  "10000000-0000-4000-8000-" + String(n).padStart(12, "0");
const from = "2026-09-30T00:00:00.000Z";
const to = "2026-10-03T00:00:00.000Z";
const window = { from, to, bucket: "day" as const, timezone: "UTC" as const };
const now = Date.parse("2026-10-03T00:00:00.000Z");
function project(n: number, total = 5, completed = 2) {
  return {
    ok: true,
    schemaVersion: 1,
    projectId: id(n),
    asOf: new Date(now).toISOString(),
    provenance: "current_rows",
    historyComplete: false,
    projectTimezone: n % 2 ? "Asia/Shanghai" : "America/Los_Angeles",
    window,
    totals: {
      taskTotal: total,
      completedTasks: completed,
      overdueTasks: 1,
      awaitingReviewTasks: 1,
      blockedTasks: 2,
      completedInWindow: completed,
    },
    difficultyDistribution: [1, 2, 3, 4, 5, null].map((stars, i) => ({
      stars,
      count: i === 5 ? total : 0,
    })),
    trends: utcDays(from, to).map((day, i) => ({
      day,
      created: i === 0 ? total : 0,
      completed: i === 1 ? completed : 0,
    })),
  };
}
function combine(rows: ReturnType<typeof project>[]) {
  return aggregateProjectAnalytics(
    rows,
    rows.map((row) => row.projectId),
    window,
    now,
  );
}

describe("C v1 contract consumer and F aggregation", () => {
  it("uses weighted completion ratio, sums six totals, all star buckets and UTC daily trends", () => {
    const one = project(1, 10, 7);
    const two = project(2, 2, 1);
    const result = combine([one, two]);
    expect(result.totals).toEqual({
      taskTotal: 12,
      completedTasks: 8,
      overdueTasks: 2,
      awaitingReviewTasks: 2,
      blockedTasks: 4,
      completedInWindow: 8,
    });
    expect(result.completionRate).toBeCloseTo(8 / 12);
    expect(result.difficultyDistribution.map((p) => p.stars)).toEqual([
      1,
      2,
      3,
      4,
      5,
      null,
    ]);
    expect(result.difficultyDistribution.map((p) => p.count)).toEqual([
      0, 0, 0, 0, 0, 12,
    ]);
    expect(result.trends).toEqual([
      { day: "2026-09-30", created: 12, completed: 0 },
      { day: "2026-10-01", created: 0, completed: 8 },
      { day: "2026-10-02", created: 0, completed: 0 },
    ]);
    expect(result.historyComplete).toBe(false);
    expect(result.provenance).toBe("current_rows");
    expect(JSON.stringify(result)).not.toMatch(
      /memberTaskDistribution|userId|assignee/,
    );
  });

  it("handles zero projects and zero tasks without dividing by zero", () => {
    expect(combine([]).completionRate).toBeNull();
    expect(combine([]).projectCount).toBe(0);
    const empty = project(1, 0, 0);
    empty.totals.overdueTasks = 0;
    empty.totals.awaitingReviewTasks = 0;
    empty.totals.blockedTasks = 0;
    expect(combine([empty]).completionRate).toBeNull();
  });

  it("accepts 100 projects and rejects 101 and duplicates", () => {
    expect(
      combine(Array.from({ length: 100 }, (_, i) => project(i + 1)))
        .projectCount,
    ).toBe(100);
    expect(() =>
      combine(Array.from({ length: 101 }, (_, i) => project(i + 1))),
    ).toThrow(ContractError);
    expect(() => combine([project(1), project(1)])).toThrow(ContractError);
  });

  it("rejects every incompatible metric schema and every unsafe number", () => {
    const invalids: ((p: ReturnType<typeof project>) => void)[] = [
      (p) => {
        p.schemaVersion = 2;
      },
      (p) => {
        p.projectId = id(99);
      },
      (p) => {
        p.historyComplete = true;
      },
      (p) => {
        p.totals.taskTotal = Number.MAX_SAFE_INTEGER + 1;
      },
      (p) => {
        p.totals.taskTotal = -1;
      },
      (p) => {
        p.totals.taskTotal = 3.5;
      },
      (p) => {
        p.totals.completedTasks = 6;
      },
      (p) => {
        p.totals.blockedTasks = Infinity;
      },
      (p) => {
        p.difficultyDistribution[5]!.count = -1;
      },
      (p) => {
        p.difficultyDistribution.splice(0, 1);
      },
      (p) => {
        p.window = { ...window, to: "2026-10-04T00:00:00.000Z" };
      },
      (p) => {
        p.trends.splice(0, 1);
      },
      (p) => {
        p.trends[0]!.day = "2026-10-01";
      },
      (p) => {
        p.asOf = "2026-10-04T00:00:00.000Z";
      },
    ];
    for (const [index, mutate] of invalids.entries()) {
      const value = project(1);
      mutate(value);
      expect(
        () => aggregateProjectAnalytics([value], [id(1)], window, now),
        `invalid case ${index}`,
      ).toThrow(ContractError);
    }
  });

  it("rejects overflow even if individual project counts are safe", () => {
    const large = project(1, Number.MAX_SAFE_INTEGER, 0);
    large.difficultyDistribution[5]!.count = Number.MAX_SAFE_INTEGER;
    large.totals.blockedTasks = 0;
    const small = project(2, 2, 1);
    expect(() => combine([large, small])).toThrow("Count overflow");
  });

  it("does not combine inconsistent project snapshot times", () => {
    const a = project(1),
      b = project(2);
    b.asOf = new Date(now - 45_000).toISOString();
    expect(() => combine([a, b])).toThrow("Inconsistent project asOf times");
  });
});
