import {
  isSubmissionFileType,
  normalizeRequiredSubmissionFileTypes,
  SUBMISSION_FILE_TYPE_OPTIONS,
  type SubmissionFileType,
} from "@/domain/submission-file-types";
import type { TaskRow } from "@/types/ui";

export type RequiredSubmissionFileType = SubmissionFileType;

export const REQUIRED_FILE_TYPE_LABELS = Object.fromEntries(
  SUBMISSION_FILE_TYPE_OPTIONS.map((option) => [option.value, option.label]),
) as Record<RequiredSubmissionFileType, string>;

export interface TaskFormModel {
  title: string;
  description: string;
  difficulty: number;
  assignmentMode: "direct" | "claimable";
  assigneeId: string;
  collaboratorIds: string[];
  startAt: string;
  deadlineAt: string;
  upstreamTaskIds: string[];
  requiredFileTypes: RequiredSubmissionFileType[];
  requiresReview: boolean;
}

export interface TaskFormCapabilities {
  startAt: boolean;
  collaborators: boolean;
  requiredFileType: boolean;
}

export interface TaskFormValidationContext {
  projectDeadlineAt?: string;
}

export function emptyTaskForm(): TaskFormModel {
  return {
    title: "",
    description: "",
    difficulty: 3,
    assignmentMode: "claimable",
    assigneeId: "",
    collaboratorIds: [],
    startAt: "",
    deadlineAt: "",
    upstreamTaskIds: [],
    requiredFileTypes: [],
    requiresReview: true,
  };
}

export function validateTaskForm(
  model: TaskFormModel,
  capabilities: TaskFormCapabilities,
  context: TaskFormValidationContext = {},
): string | null {
  if (!model.title.trim()) return "请填写任务名称";
  if (model.assignmentMode === "direct" && !model.assigneeId)
    return "请选择主负责人";
  if (!model.deadlineAt || !Number.isFinite(Date.parse(model.deadlineAt)))
    return "请填写有效的截止时间";
  if (
    context.projectDeadlineAt &&
    Number.isFinite(Date.parse(context.projectDeadlineAt)) &&
    Date.parse(model.deadlineAt) > Date.parse(context.projectDeadlineAt)
  ) {
    return "任务截止时间不能晚于项目 DDL";
  }
  if (
    capabilities.startAt &&
    model.startAt &&
    Date.parse(model.startAt) >= Date.parse(model.deadlineAt)
  ) {
    return "开始时间必须早于截止时间";
  }
  if (
    capabilities.collaborators &&
    model.assigneeId &&
    model.collaboratorIds.includes(model.assigneeId)
  ) {
    return "主负责人不能同时作为协作者";
  }
  return null;
}

export function createTaskFormFromTask(
  task: TaskRow,
  upstreamTaskIds: readonly string[] = [],
): TaskFormModel {
  return {
    title: task.title,
    description: task.description ?? "",
    difficulty: Math.max(1, Math.min(5, Math.round(task.weight || 1))),
    assignmentMode: task.assignee_id ? "direct" : "claimable",
    assigneeId: task.assignee_id ?? "",
    collaboratorIds: [],
    startAt: "",
    deadlineAt: task.deadline_at.slice(0, 16),
    upstreamTaskIds: [...upstreamTaskIds],
    requiredFileTypes: normalizeRequiredSubmissionFileTypes(
      task.required_submission_file_types ??
        (isSubmissionFileType(task.required_submission_file_type)
          ? [task.required_submission_file_type]
          : []),
    ),
    requiresReview: task.requires_review,
  };
}

export interface TaskChangeFact {
  label: string;
  before: string;
  after: string;
}

export function taskChangeFacts(
  before: TaskFormModel,
  after: TaskFormModel,
): TaskChangeFact[] {
  const facts: TaskChangeFact[] = [];
  if (before.deadlineAt !== after.deadlineAt) {
    facts.push({
      label: "DDL",
      before: before.deadlineAt,
      after: after.deadlineAt,
    });
  }
  if (before.assigneeId !== after.assigneeId) {
    facts.push({
      label: "主负责人",
      before: before.assigneeId || "开放认领",
      after: after.assigneeId || "开放认领",
    });
  }
  if (before.difficulty !== after.difficulty) {
    facts.push({
      label: "任务难度",
      before: `${before.difficulty} 星`,
      after: `${after.difficulty} 星`,
    });
  }
  if (
    before.requiredFileTypes.join(",") !== after.requiredFileTypes.join(",")
  ) {
    const formatLabel = (types: readonly RequiredSubmissionFileType[]) =>
      types.map((type) => REQUIRED_FILE_TYPE_LABELS[type]).join("、") ||
      "不限制";
    facts.push({
      label: "提交要求",
      before: formatLabel(before.requiredFileTypes),
      after: formatLabel(after.requiredFileTypes),
    });
  }
  return facts;
}
