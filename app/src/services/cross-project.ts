import { getBackend } from "@/services/backend";

export interface CrossProject {
  projectId: string;
  name: string;
  courseName: string | null;
  timezone: string;
  deadlineAt: string | null;
  lifecycleState: "active" | "contribution_review" | "completed";
}
export interface CrossProjectPage {
  ok: true;
  schemaVersion: 1;
  projects: CrossProject[];
  nextCursor: string | null;
}

export type CrossProjectTotals = {
  taskTotal: number;
  completedTasks: number;
  overdueTasks: number;
  awaitingReviewTasks: number;
  blockedTasks: number;
  completedInWindow: number;
};
export interface CrossProjectAnalytics {
  ok: true;
  schemaVersion: 1;
  scope: "account";
  asOf: string;
  window: { from: string; to: string; bucket: "day"; timezone: "UTC" };
  provenance: "current_rows";
  historyComplete: false;
  projectCount: number;
  totals: CrossProjectTotals;
  completionRate: number | null;
  difficultyDistribution: { stars: number | null; count: number }[];
  trends: { day: string; created: number; completed: number }[];
  projects: (Pick<
    CrossProjectTotals,
    | "taskTotal"
    | "completedTasks"
    | "overdueTasks"
    | "blockedTasks"
    | "awaitingReviewTasks"
  > & { projectId: string })[];
}

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MESSAGES: Record<string, string> = {
  UNAUTHENTICATED: "请重新登录后访问跨项目工作台。",
  CAPABILITY_NOT_AVAILABLE: "此 Pro 功能尚未发布，当前无法使用。",
  CAPABILITY_REQUIRES_PRO: "此功能仅对有效账号 Pro 开放。",
  NOT_FOUND_OR_NOT_AUTHORIZED: "项目成员权限已发生变化，请刷新后重试。",
  VALIDATION_FAILED: "搜索或日期参数无效，请检查。",
  QUERY_LIMIT_EXCEEDED: "单次最多汇总 100 个项目，请缩小选择范围。",
  SERVICE_UNAVAILABLE: "跨项目统计服务尚未就绪，请稍后重试。",
};

export class CrossProjectError extends Error {
  constructor(public readonly code: string) {
    super(MESSAGES[code] ?? "跨项目请求失败，请稍后重试。");
    this.name = "CrossProjectError";
  }
}

function expectObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new CrossProjectError("SERVICE_UNAVAILABLE");
  return value as Record<string, unknown>;
}
function unwrap<T>(raw: unknown): T {
  const value = expectObject(raw);
  if (value.ok !== true) {
    throw new CrossProjectError(
      typeof value.code === "string" ? value.code : "SERVICE_UNAVAILABLE",
    );
  }
  if (value.schemaVersion !== 1)
    throw new CrossProjectError("SERVICE_UNAVAILABLE");
  return value as T;
}

function validatePage(value: CrossProjectPage) {
  if (
    !Array.isArray(value.projects) ||
    value.projects.length > 100 ||
    (value.nextCursor !== null && !UUID.test(value.nextCursor)) ||
    value.projects.some(
      (p) =>
        !p ||
        !UUID.test(p.projectId) ||
        typeof p.name !== "string" ||
        typeof p.timezone !== "string" ||
        !["active", "contribution_review", "completed"].includes(
          p.lifecycleState,
        ),
    )
  )
    throw new CrossProjectError("SERVICE_UNAVAILABLE");
  return value;
}

export async function searchCrossProjects(
  search: string,
  cursor: string | null = null,
  limit = 50,
): Promise<CrossProjectPage> {
  const backend = getBackend();
  if (!backend) throw new CrossProjectError("SERVICE_UNAVAILABLE");
  if (search.trim().length > 100 || limit < 1 || limit > 100)
    throw new CrossProjectError("VALIDATION_FAILED");
  // F's RPC is not added to shared generated types until G integration.
  const client = backend.client as unknown as {
    rpc: (
      name: string,
      args: object,
    ) => Promise<{ data: unknown; error: unknown }>;
  };
  const { data, error } = await client.rpc("get_my_cross_project_projects", {
    p_search: search.trim() || null,
    p_limit: limit,
    p_after_project_id: cursor,
  });
  if (error) throw new CrossProjectError("SERVICE_UNAVAILABLE");
  return validatePage(unwrap<CrossProjectPage>(data));
}

export async function loadCrossProjectAnalytics(input: {
  from: string;
  to: string;
  projectIds?: string[];
}): Promise<CrossProjectAnalytics> {
  const backend = getBackend();
  if (!backend) throw new CrossProjectError("SERVICE_UNAVAILABLE");
  const { data, error } = await backend.client.functions.invoke(
    "cross-project-analytics",
    { body: input },
  );
  if (error) {
    // Supabase's SDK exposes the HTTP response on FunctionsHttpError.context.
    const context = (error as { context?: unknown }).context;
    if (context instanceof Response) {
      try {
        const body = expectObject(await context.json());
        if (typeof body.code === "string")
          throw new CrossProjectError(body.code);
      } catch (cause) {
        if (cause instanceof CrossProjectError) throw cause;
      }
    }
    throw new CrossProjectError("SERVICE_UNAVAILABLE");
  }
  const result = unwrap<CrossProjectAnalytics>(data);
  if (
    result.scope !== "account" ||
    !Array.isArray(result.projects) ||
    !Array.isArray(result.trends) ||
    !Array.isArray(result.difficultyDistribution) ||
    result.historyComplete !== false
  )
    throw new CrossProjectError("SERVICE_UNAVAILABLE");
  return result;
}
