import type { SubmissionFileType } from "@/domain/submission-file-types";

export const AI_BREAKDOWN = {
  minPromptChars: 10,
  maxPromptChars: 4000,
  minTasks: 2,
  maxTasks: 8,
  defaultTasks: 4,
  minDurationDays: 1,
  maxDurationDays: 30,
  defaultWeight: 3,
} as const;

export interface AiBreakdownItem {
  title: string;
  description: string;
  durationDays: number;
  fileTypes: SubmissionFileType[];
}

export interface AiTaskDraft extends AiBreakdownItem {
  /** Client-side identity; drafts live only in the current view session. */
  key: string;
  selected: boolean;
  deadlineAt: string;
}

export function clampDuration(days: number): number {
  if (!Number.isFinite(days)) return 3;
  return Math.min(
    AI_BREAKDOWN.maxDurationDays,
    Math.max(AI_BREAKDOWN.minDurationDays, Math.round(days)),
  );
}

/**
 * Distributes task deadlines inside the project DDL, weighted by each task's
 * suggested duration: longer tasks sit closer to the DDL, and no deadline
 * ever falls after the project DDL. Falls back to spreading forward from
 * `nowMs` when the project deadline is missing or invalid.
 */
export function suggestDeadlines(
  items: ReadonlyArray<{ durationDays: number }>,
  projectDeadlineAt: string,
  nowMs: number = Date.now(),
): string[] {
  const total = items.reduce(
    (sum, item) => sum + clampDuration(item.durationDays),
    0,
  );
  if (total <= 0) return [];
  const parsed = Date.parse(projectDeadlineAt);
  const ddl = Number.isFinite(parsed) ? parsed : nowMs + total * 86_400_000;
  const available = Math.max(0, ddl - nowMs);
  let before = 0;
  return items.map((item) => {
    before += clampDuration(item.durationDays);
    return new Date(
      Math.min(ddl, nowMs + available * (before / total)),
    ).toISOString();
  });
}

export function createDrafts(
  items: ReadonlyArray<AiBreakdownItem>,
  projectDeadlineAt: string,
  nowMs: number = Date.now(),
): AiTaskDraft[] {
  const deadlines = suggestDeadlines(items, projectDeadlineAt, nowMs);
  return items.map((item, index) => ({
    key: `ai-${index}-${item.title.slice(0, 8)}`,
    title: item.title,
    description: item.description,
    durationDays: clampDuration(item.durationDays),
    fileTypes: item.fileTypes,
    selected: true,
    deadlineAt: deadlines[index] ?? "",
  }));
}

export type AiTaskCreateInput = {
  title: string;
  description?: string;
  deadlineAt: string;
  assignmentMode: "claimable";
  requiredSubmissionFileTypes: SubmissionFileType[];
  requiresReview: true;
  weight?: number;
};

export function draftToTaskInput(draft: AiTaskDraft): AiTaskCreateInput {
  return {
    title: draft.title.trim(),
    description: draft.description.trim() || undefined,
    deadlineAt: draft.deadlineAt,
    assignmentMode: "claimable",
    requiredSubmissionFileTypes: draft.fileTypes,
    requiresReview: true,
  };
}

/**
 * Weighted projects require a 1–5 difficulty score on every task;
 * facts-only projects reject one. Mirrors the task form's default (3).
 */
export function resolveDraftWeight(
  contributionMode: string | null | undefined,
): number | undefined {
  return contributionMode === "facts_only"
    ? undefined
    : AI_BREAKDOWN.defaultWeight;
}

export function validateDraft(
  draft: AiTaskDraft,
  projectDeadlineAt: string,
  nowMs: number = Date.now(),
): string | null {
  if (!draft.title.trim()) return "请填写任务名称";
  const deadline = Date.parse(draft.deadlineAt);
  if (!Number.isFinite(deadline) || deadline <= nowMs)
    return "任务截止时间必须晚于当前时间";
  const ddl = Date.parse(projectDeadlineAt);
  if (Number.isFinite(ddl) && deadline > ddl)
    return "任务截止时间不能晚于项目 DDL";
  return null;
}
