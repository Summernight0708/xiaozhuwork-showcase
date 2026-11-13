import { clampDuration, type AiBreakdownItem } from "@/domain/ai-breakdown";
import {
  isSubmissionFileType,
  sortSubmissionFileTypes,
  type SubmissionFileType,
} from "@/domain/submission-file-types";
import { getBackend } from "./backend";

export type AiBreakdownResult = {
  items: AiBreakdownItem[];
  model: string;
};

export class AiTaskBreakdownError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "AiTaskBreakdownError";
  }
}

const ERROR_LABELS: Record<string, string> = {
  UNAUTHENTICATED: "登录已失效，请重新登录",
  CAPABILITY_NOT_AVAILABLE: "AI 拆解能力尚未配置，请稍后再试",
  VALIDATION_FAILED: "作业描述无效，请检查后重试",
  RATE_LIMITED: "请求过于频繁，请稍后再试",
  SERVICE_UNAVAILABLE: "AI 服务暂时不可用，请稍后重试",
};

export function aiTaskBreakdownErrorMessage(error: unknown): string {
  if (error instanceof AiTaskBreakdownError)
    return ERROR_LABELS[error.code] ?? ERROR_LABELS.SERVICE_UNAVAILABLE!;
  if (error instanceof Error && error.name === "AbortError")
    return "已取消生成";
  return ERROR_LABELS.SERVICE_UNAVAILABLE!;
}

export function isAiTaskBreakdownAbort(error: unknown): boolean {
  return error instanceof Error && error.name === "AbortError";
}

export async function requestAiTaskBreakdown(
  prompt: string,
  taskCount: number,
  signal?: AbortSignal,
): Promise<AiBreakdownResult> {
  const backend = getBackend();
  if (!backend) throw new AiTaskBreakdownError("SERVICE_UNAVAILABLE");
  if (signal?.aborted)
    throw new DOMException("Request cancelled", "AbortError");
  const { data, error } = await backend.client.functions.invoke(
    "ai-task-breakdown",
    { body: { prompt, taskCount }, signal },
  );
  if (signal?.aborted)
    throw new DOMException("Request cancelled", "AbortError");
  if (error) {
    const context = (error as { context?: unknown }).context;
    if (context instanceof Response) {
      try {
        const body: unknown = await context.clone().json();
        const code =
          body && typeof body === "object"
            ? (body as { code?: unknown }).code
            : undefined;
        if (typeof code === "string") throw new AiTaskBreakdownError(code);
      } catch (caught) {
        if (caught instanceof AiTaskBreakdownError) throw caught;
      }
    }
    throw new AiTaskBreakdownError("SERVICE_UNAVAILABLE");
  }
  return normalizeBreakdownPayload(data);
}

function normalizeBreakdownPayload(payload: unknown): AiBreakdownResult {
  if (!payload || typeof payload !== "object" || Array.isArray(payload))
    throw new AiTaskBreakdownError("SERVICE_UNAVAILABLE");
  const envelope = payload as Record<string, unknown>;
  const data = envelope.data;
  if (
    envelope.ok !== true ||
    !data ||
    typeof data !== "object" ||
    Array.isArray(data)
  ) {
    throw new AiTaskBreakdownError("SERVICE_UNAVAILABLE");
  }
  const body = data as Record<string, unknown>;
  const rawItems = body.items;
  if (!Array.isArray(rawItems) || rawItems.length === 0)
    throw new AiTaskBreakdownError("SERVICE_UNAVAILABLE");
  const items: AiBreakdownItem[] = [];
  for (const raw of rawItems) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    const entry = raw as Record<string, unknown>;
    const title = typeof entry.title === "string" ? entry.title.trim() : "";
    if (!title) continue;
    const description =
      typeof entry.description === "string" ? entry.description : "";
    const durationDays = clampDuration(
      typeof entry.durationDays === "number" ? entry.durationDays : NaN,
    );
    const fileTypes: SubmissionFileType[] = sortSubmissionFileTypes(
      Array.isArray(entry.fileTypes)
        ? entry.fileTypes.filter(isSubmissionFileType).slice(0, 3)
        : [],
    );
    items.push({ title, description, durationDays, fileTypes });
  }
  if (items.length === 0) throw new AiTaskBreakdownError("SERVICE_UNAVAILABLE");
  const model = typeof body.model === "string" ? body.model : "";
  return { items, model };
}
