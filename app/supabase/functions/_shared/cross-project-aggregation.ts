/** F: pure schema-v1 consumer. Never calculates project metrics from task rows. */
export const TOTAL_KEYS = [
  "taskTotal",
  "completedTasks",
  "overdueTasks",
  "awaitingReviewTasks",
  "blockedTasks",
  "completedInWindow",
] as const;
type TotalKey = (typeof TOTAL_KEYS)[number];
type Totals = Record<TotalKey, number>;
type Bucket = { stars: number | null; count: number };
type Trend = { day: string; created: number; completed: number };
export type Window = {
  from: string;
  to: string;
  bucket: "day";
  timezone: "UTC";
};

export class ContractError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ContractError";
  }
}

export function safeCount(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0)
    throw new ContractError("Unsafe count");
  return value as number;
}

function safeAdd(left: number, right: number) {
  const sum = left + right;
  if (!Number.isSafeInteger(sum)) throw new ContractError("Count overflow");
  return sum;
}

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new ContractError("Expected object");
  return value as Record<string, unknown>;
}

function instant(value: unknown): number {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value)))
    throw new ContractError("Invalid timestamp");
  return Date.parse(value);
}

export function utcDays(from: string, to: string): string[] {
  const first = Date.parse(from);
  const end = Date.parse(to);
  if (!Number.isFinite(first) || !Number.isFinite(end) || first >= end)
    throw new ContractError("Invalid window");
  const dates: string[] = [];
  const dayMs = 86_400_000;
  for (let t = Math.floor(first / dayMs) * dayMs; t < end; t += dayMs) {
    dates.push(new Date(t).toISOString().slice(0, 10));
    if (dates.length > 181) throw new ContractError("Too many days");
  }
  return dates;
}

type ProjectData = {
  projectId: string;
  asOf: string;
  totals: Totals;
  difficultyDistribution: Bucket[];
  trends: Trend[];
};

export function parseProjectAnalytics(
  raw: unknown,
  expectedId: string,
  window: Window,
  nowMs: number,
): ProjectData {
  const data = object(raw);
  if (
    data.ok !== true ||
    data.schemaVersion !== 1 ||
    data.projectId !== expectedId ||
    data.provenance !== "current_rows" ||
    data.historyComplete !== false ||
    typeof data.projectTimezone !== "string" ||
    !data.projectTimezone
  )
    throw new ContractError("Project contract identity");
  const actualWindow = object(data.window);
  if (
    actualWindow.bucket !== "day" ||
    actualWindow.timezone !== "UTC" ||
    instant(actualWindow.from) !== instant(window.from) ||
    instant(actualWindow.to) !== instant(window.to)
  )
    throw new ContractError("Project window mismatch");
  const asOfMs = instant(data.asOf);
  if (Math.abs(asOfMs - nowMs) > 60_000)
    throw new ContractError("Project asOf out of bounds");
  const totalsObj = object(data.totals);
  const totals = {} as Totals;
  for (const key of TOTAL_KEYS) totals[key] = safeCount(totalsObj[key]);
  if (
    totals.completedTasks > totals.taskTotal ||
    totals.completedInWindow > totals.completedTasks ||
    totals.overdueTasks > totals.taskTotal ||
    totals.blockedTasks > totals.taskTotal ||
    totals.awaitingReviewTasks > totals.taskTotal
  )
    throw new ContractError("Inconsistent counters");

  if (
    !Array.isArray(data.difficultyDistribution) ||
    data.difficultyDistribution.length !== 6
  )
    throw new ContractError("Invalid difficulty buckets");
  const difficultyDistribution = data.difficultyDistribution.map(
    (rawBucket, i) => {
      const bucket = object(rawBucket);
      if (bucket.stars !== (i === 5 ? null : i + 1))
        throw new ContractError("Invalid difficulty order");
      return {
        stars: bucket.stars as number | null,
        count: safeCount(bucket.count),
      };
    },
  );
  const difficultySum = difficultyDistribution.reduce(
    (sum, bucket) => safeAdd(sum, bucket.count),
    0,
  );
  if (difficultySum !== totals.taskTotal)
    throw new ContractError("Difficulty sum mismatch");

  const days = utcDays(window.from, window.to);
  if (!Array.isArray(data.trends) || data.trends.length !== days.length)
    throw new ContractError("Missing UTC date bucket");
  const trends = data.trends.map((rawTrend, i) => {
    const trend = object(rawTrend);
    if (trend.day !== days[i])
      throw new ContractError("Nonmatching UTC date bucket");
    return {
      day: days[i]!,
      created: safeCount(trend.created),
      completed: safeCount(trend.completed),
    };
  });
  return {
    projectId: expectedId,
    asOf: new Date(asOfMs).toISOString(),
    totals,
    difficultyDistribution,
    trends,
  };
}

export function aggregateProjectAnalytics(
  responses: readonly unknown[],
  projectIds: readonly string[],
  window: Window,
  nowMs = Date.now(),
) {
  if (
    projectIds.length > 100 ||
    new Set(projectIds).size !== projectIds.length ||
    responses.length !== projectIds.length
  )
    throw new ContractError("Nonunique or missing project responses");
  const projects = responses.map((response, i) =>
    parseProjectAnalytics(response, projectIds[i]!, window, nowMs),
  );
  const asOfTimes = projects.map((item) => Date.parse(item.asOf));
  if (
    asOfTimes.length &&
    Math.max(...asOfTimes) - Math.min(...asOfTimes) > 30_000
  )
    throw new ContractError("Inconsistent project asOf times");

  const totals = Object.fromEntries(
    TOTAL_KEYS.map((key) => [key, 0]),
  ) as Totals;
  const difficultyDistribution: Bucket[] = [1, 2, 3, 4, 5, null].map(
    (stars) => ({ stars, count: 0 }),
  );
  const trends: Trend[] = utcDays(window.from, window.to).map((day) => ({
    day,
    created: 0,
    completed: 0,
  }));
  const summaries = projects.map((project) => {
    for (const key of TOTAL_KEYS)
      totals[key] = safeAdd(totals[key], project.totals[key]);
    for (let i = 0; i < 6; i++)
      difficultyDistribution[i]!.count = safeAdd(
        difficultyDistribution[i]!.count,
        project.difficultyDistribution[i]!.count,
      );
    for (let i = 0; i < trends.length; i++) {
      trends[i]!.created = safeAdd(
        trends[i]!.created,
        project.trends[i]!.created,
      );
      trends[i]!.completed = safeAdd(
        trends[i]!.completed,
        project.trends[i]!.completed,
      );
    }
    return {
      projectId: project.projectId,
      taskTotal: project.totals.taskTotal,
      completedTasks: project.totals.completedTasks,
      overdueTasks: project.totals.overdueTasks,
      blockedTasks: project.totals.blockedTasks,
      awaitingReviewTasks: project.totals.awaitingReviewTasks,
    };
  });
  const distributionTotal = difficultyDistribution.reduce(
    (sum, bucket) => safeAdd(sum, bucket.count),
    0,
  );
  if (distributionTotal !== totals.taskTotal)
    throw new ContractError("Aggregate difficulty sum mismatch");
  return {
    ok: true as const,
    schemaVersion: 1 as const,
    scope: "account" as const,
    asOf: projects.length
      ? new Date(Math.max(...asOfTimes)).toISOString()
      : new Date(nowMs).toISOString(),
    window,
    provenance: "current_rows" as const,
    historyComplete: false as const,
    projectCount: projects.length,
    totals,
    completionRate:
      totals.taskTotal === 0 ? null : totals.completedTasks / totals.taskTotal,
    difficultyDistribution,
    trends,
    projects: summaries,
  };
}
