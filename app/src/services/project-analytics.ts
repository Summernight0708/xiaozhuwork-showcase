export type ProjectAnalyticsFailureCode =
  | "UNAUTHENTICATED"
  | "NOT_FOUND_OR_NOT_AUTHORIZED"
  | "VALIDATION_FAILED"
  | "CAPABILITY_NOT_AVAILABLE"
  | "CAPABILITY_REQUIRES_PRO"
  | "SERVICE_UNAVAILABLE";

export interface ProjectAnalyticsRequest {
  projectId: string;
  from: string;
  to: string;
}

export interface ProjectAnalyticsTotals {
  taskTotal: number;
  completedTasks: number;
  overdueTasks: number;
  awaitingReviewTasks: number;
  blockedTasks: number;
  completedInWindow: number;
}

export interface ProjectAnalytics {
  ok: true;
  schemaVersion: 1;
  projectId: string;
  asOf: string;
  provenance: "current_rows";
  historyComplete: false;
  projectTimezone: string;
  window: {
    from: string;
    to: string;
    bucket: "day";
    timezone: "UTC";
  };
  totals: ProjectAnalyticsTotals;
  memberTaskDistribution: Array<{
    kind: "active_member" | "former_member" | "unassigned";
    userId: string | null;
    count: number;
  }>;
  difficultyDistribution: Array<{
    stars: 1 | 2 | 3 | 4 | 5 | null;
    count: number;
  }>;
  completionTiming: {
    count: number;
    averageSeconds: number | null;
    medianSeconds: number | null;
    invalidTimeRows: number;
  };
  projectCycle: {
    startAt: string;
    startSource: "start_at" | "created_at";
    deadlineAt: string;
    completedAt: string | null;
    completedCycleSeconds: number | null;
    elapsedSeconds: number;
  };
  trends: Array<{ day: string; created: number; completed: number }>;
  dataIssues: {
    completedMissingTime: number;
    historicalStatusReconstructionAvailable: false;
    collaboratorCreditAvailable: false;
  };
}

export interface ProjectAnalyticsFailure {
  ok: false;
  code: ProjectAnalyticsFailureCode;
}

export type ProjectAnalyticsResult = ProjectAnalytics | ProjectAnalyticsFailure;

interface AnalyticsRpcPort {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: unknown }>;
}

const DAY_MS = 86_400_000;
const MAX_WINDOW_MS = 180 * DAY_MS;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const SAFE_FAILURE_CODES = new Set<ProjectAnalyticsFailureCode>([
  "UNAUTHENTICATED",
  "NOT_FOUND_OR_NOT_AUTHORIZED",
  "VALIDATION_FAILED",
  "CAPABILITY_NOT_AVAILABLE",
  "CAPABILITY_REQUIRES_PRO",
  "SERVICE_UNAVAILABLE",
]);

export class ProjectAnalyticsServiceError extends Error {
  readonly code: ProjectAnalyticsFailureCode;

  constructor(
    code: ProjectAnalyticsFailureCode,
    message = "Project analytics response was unavailable or invalid",
  ) {
    super(message);
    this.name = "ProjectAnalyticsServiceError";
    this.code = code;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isSafeCount(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function isNullableSafeNumber(value: unknown): value is number | null {
  return value === null || isSafeCount(value);
}

function isInstant(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /(Z|[+-]\d{2}:\d{2})$/i.test(value) &&
    Number.isFinite(Date.parse(value))
  );
}

function expectRecord(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }
  return value;
}

function expectSafeCount(value: unknown): number {
  if (!isSafeCount(value)) {
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }
  return value;
}

function parseTotals(value: unknown): ProjectAnalyticsTotals {
  const record = expectRecord(value);
  return {
    taskTotal: expectSafeCount(record.taskTotal),
    completedTasks: expectSafeCount(record.completedTasks),
    overdueTasks: expectSafeCount(record.overdueTasks),
    awaitingReviewTasks: expectSafeCount(record.awaitingReviewTasks),
    blockedTasks: expectSafeCount(record.blockedTasks),
    completedInWindow: expectSafeCount(record.completedInWindow),
  };
}

function parseMemberDistribution(
  value: unknown,
  taskTotal: number,
): ProjectAnalytics["memberTaskDistribution"] {
  if (!Array.isArray(value)) {
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }
  const distribution = value.map((item) => {
    const record = expectRecord(item);
    const kind = record.kind;
    const userId = record.userId;
    if (
      (kind !== "active_member" &&
        kind !== "former_member" &&
        kind !== "unassigned") ||
      (kind === "active_member" ? typeof userId !== "string" : userId !== null)
    ) {
      throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
    }
    return {
      kind: kind as "active_member" | "former_member" | "unassigned",
      userId: userId as string | null,
      count: expectSafeCount(record.count),
    };
  });
  if (distribution.reduce((sum, item) => sum + item.count, 0) !== taskTotal) {
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }
  return distribution;
}

function parseDifficultyDistribution(
  value: unknown,
  taskTotal: number,
): ProjectAnalytics["difficultyDistribution"] {
  if (!Array.isArray(value) || value.length !== 6) {
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }
  const expectedStars = [1, 2, 3, 4, 5, null] as const;
  const distribution = value.map((item, index) => {
    const record = expectRecord(item);
    const stars = record.stars;
    if (stars !== expectedStars[index]) {
      throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
    }
    return {
      stars: stars as 1 | 2 | 3 | 4 | 5 | null,
      count: expectSafeCount(record.count),
    };
  });
  if (distribution.reduce((sum, item) => sum + item.count, 0) !== taskTotal) {
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }
  return distribution;
}

function parseTrends(value: unknown): ProjectAnalytics["trends"] {
  if (!Array.isArray(value)) {
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }
  let previousDay = "";
  return value.map((item) => {
    const record = expectRecord(item);
    if (
      typeof record.day !== "string" ||
      !DATE_PATTERN.test(record.day) ||
      record.day <= previousDay
    ) {
      throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
    }
    previousDay = record.day;
    return {
      day: record.day,
      created: expectSafeCount(record.created),
      completed: expectSafeCount(record.completed),
    };
  });
}

export function validateProjectAnalyticsRequest(
  request: ProjectAnalyticsRequest,
): ProjectAnalyticsRequest {
  if (!UUID_PATTERN.test(request.projectId)) {
    throw new ProjectAnalyticsServiceError(
      "VALIDATION_FAILED",
      "Invalid project identifier",
    );
  }
  if (!isInstant(request.from) || !isInstant(request.to)) {
    throw new ProjectAnalyticsServiceError(
      "VALIDATION_FAILED",
      "Analytics window must use ISO timestamps with an explicit timezone",
    );
  }
  const from = Date.parse(request.from);
  const to = Date.parse(request.to);
  if (from >= to) {
    throw new ProjectAnalyticsServiceError(
      "VALIDATION_FAILED",
      "Analytics window must be half-open with from before to",
    );
  }
  if (to - from > MAX_WINDOW_MS) {
    throw new ProjectAnalyticsServiceError(
      "VALIDATION_FAILED",
      "Analytics window cannot exceed 180 days",
    );
  }
  return request;
}

export function createDefaultAnalyticsWindow(now = new Date()): {
  from: string;
  to: string;
} {
  const to = now.toISOString();
  return {
    from: new Date(now.getTime() - 30 * DAY_MS).toISOString(),
    to,
  };
}

export function projectAnalyticsFailurePresentation(
  code: ProjectAnalyticsFailureCode,
): { title: string; detail: string } {
  switch (code) {
    case "CAPABILITY_NOT_AVAILABLE":
      return {
        title: "项目分析尚未发布",
        detail: "此能力仍在发布准备中，现有项目概览不受影响。",
      };
    case "CAPABILITY_REQUIRES_PRO":
      return {
        title: "项目分析需要 Pro",
        detail: "当前项目不在 Pro 或宽限期内，可继续使用基础项目视图。",
      };
    case "NOT_FOUND_OR_NOT_AUTHORIZED":
      return {
        title: "无法访问此项目",
        detail: "项目不存在，或你的成员身份已发生变化。",
      };
    case "UNAUTHENTICATED":
      return {
        title: "登录状态已失效",
        detail: "请重新登录后再查看项目分析。",
      };
    case "VALIDATION_FAILED":
      return {
        title: "时间范围无效",
        detail: "请选择不超过 180 天、开始早于结束的 UTC 时间范围。",
      };
    default:
      return {
        title: "项目分析暂时不可用",
        detail: "服务未返回可验证的数据，请稍后重试。",
      };
  }
}

export function parseProjectAnalyticsResponse(
  value: unknown,
): ProjectAnalyticsResult {
  const record = expectRecord(value);
  if (record.ok === false) {
    if (
      typeof record.code === "string" &&
      SAFE_FAILURE_CODES.has(record.code as ProjectAnalyticsFailureCode)
    ) {
      return {
        ok: false,
        code: record.code as ProjectAnalyticsFailureCode,
      };
    }
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }
  if (record.ok !== true || record.schemaVersion !== 1) {
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }

  const window = expectRecord(record.window);
  const totals = parseTotals(record.totals);
  const completionTiming = expectRecord(record.completionTiming);
  const projectCycle = expectRecord(record.projectCycle);
  const dataIssues = expectRecord(record.dataIssues);
  if (
    typeof record.projectId !== "string" ||
    !UUID_PATTERN.test(record.projectId) ||
    !isInstant(record.asOf) ||
    record.provenance !== "current_rows" ||
    record.historyComplete !== false ||
    typeof record.projectTimezone !== "string" ||
    record.projectTimezone.length === 0 ||
    !isInstant(window.from) ||
    !isInstant(window.to) ||
    window.bucket !== "day" ||
    window.timezone !== "UTC" ||
    !isSafeCount(completionTiming.count) ||
    !isNullableSafeNumber(completionTiming.averageSeconds) ||
    !isNullableSafeNumber(completionTiming.medianSeconds) ||
    !isSafeCount(completionTiming.invalidTimeRows) ||
    !isInstant(projectCycle.startAt) ||
    (projectCycle.startSource !== "start_at" &&
      projectCycle.startSource !== "created_at") ||
    !isInstant(projectCycle.deadlineAt) ||
    (projectCycle.completedAt !== null &&
      !isInstant(projectCycle.completedAt)) ||
    !isNullableSafeNumber(projectCycle.completedCycleSeconds) ||
    !isSafeCount(projectCycle.elapsedSeconds) ||
    !isSafeCount(dataIssues.completedMissingTime) ||
    dataIssues.historicalStatusReconstructionAvailable !== false ||
    dataIssues.collaboratorCreditAvailable !== false
  ) {
    throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
  }

  return {
    ok: true,
    schemaVersion: 1,
    projectId: record.projectId,
    asOf: record.asOf,
    provenance: "current_rows",
    historyComplete: false,
    projectTimezone: record.projectTimezone,
    window: {
      from: window.from,
      to: window.to,
      bucket: "day",
      timezone: "UTC",
    },
    totals,
    memberTaskDistribution: parseMemberDistribution(
      record.memberTaskDistribution,
      totals.taskTotal,
    ),
    difficultyDistribution: parseDifficultyDistribution(
      record.difficultyDistribution,
      totals.taskTotal,
    ),
    completionTiming: {
      count: completionTiming.count,
      averageSeconds: completionTiming.averageSeconds,
      medianSeconds: completionTiming.medianSeconds,
      invalidTimeRows: completionTiming.invalidTimeRows,
    },
    projectCycle: {
      startAt: projectCycle.startAt,
      startSource: projectCycle.startSource,
      deadlineAt: projectCycle.deadlineAt,
      completedAt: projectCycle.completedAt,
      completedCycleSeconds: projectCycle.completedCycleSeconds,
      elapsedSeconds: projectCycle.elapsedSeconds,
    },
    trends: parseTrends(record.trends),
    dataIssues: {
      completedMissingTime: dataIssues.completedMissingTime,
      historicalStatusReconstructionAvailable: false,
      collaboratorCreditAvailable: false,
    },
  };
}

export function createProjectAnalyticsService(client: AnalyticsRpcPort) {
  return {
    async getProjectAnalytics(
      request: ProjectAnalyticsRequest,
    ): Promise<ProjectAnalyticsResult> {
      validateProjectAnalyticsRequest(request);
      let response: Awaited<ReturnType<AnalyticsRpcPort["rpc"]>>;
      try {
        response = await client.rpc("get_project_analytics", {
          p_project_id: request.projectId,
          p_from: request.from,
          p_to: request.to,
        });
      } catch {
        throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
      }
      if (response.error) {
        throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
      }
      const result = parseProjectAnalyticsResponse(response.data);
      if (
        result.ok &&
        (result.projectId !== request.projectId ||
          Date.parse(result.window.from) !== Date.parse(request.from) ||
          Date.parse(result.window.to) !== Date.parse(request.to))
      ) {
        throw new ProjectAnalyticsServiceError("SERVICE_UNAVAILABLE");
      }
      return result;
    },
  };
}
