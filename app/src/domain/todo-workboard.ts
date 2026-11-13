import type { ReviewRoundRow, TaskRow } from "@/types/ui";

export type WorkBoardColumnId =
  "not_started" | "in_progress" | "blocked" | "completed";

export type WorkResponsibility = {
  kind: "primary" | "collaborator";
  collaboratorCount?: number;
};

export interface WorkTaskInput {
  task: TaskRow;
  projectId: string;
  projectName: string;
  responsibility?: WorkResponsibility;
  dependencyBlocked?: boolean;
  upstreamTitle?: string | null;
  latestReviewDecision?: string | null;
  latestReviewReason?: string | null;
}

export interface ProjectWorkInputOptions {
  tasks: readonly TaskRow[];
  reviews: readonly ReviewRoundRow[];
  projectId: string;
  projectName: string;
  currentUserId: string | null;
  isAcceptedCollaborator: (taskId: string) => boolean;
  taskResponsibilityKind?: (
    task: TaskRow,
  ) => "primary" | "collaborator" | null | undefined;
  collaboratorsForTask?: (taskId: string) => Array<{ state: string }>;
  dependencyState?: (taskId: string) => { blocked: boolean };
  upstreamTasks?: (taskId: string) => TaskRow[];
}

export interface WorkTaskItem extends WorkTaskInput {
  column: WorkBoardColumnId;
  needsChanges: boolean;
  overdue: boolean;
  dueSoon: boolean;
  statusLabel: string;
  statusDetail?: string;
}

export interface WorkBoardModel {
  columns: Record<WorkBoardColumnId, WorkTaskItem[]>;
  completedTotal: number;
}

export const WORK_BOARD_COLUMNS: Array<{
  id: WorkBoardColumnId;
  label: string;
}> = [
  { id: "not_started", label: "待开始" },
  { id: "in_progress", label: "进行中" },
  { id: "blocked", label: "阻塞 / 待上游" },
  { id: "completed", label: "已完成" },
];

const DAY = 86_400_000;

function latestReview(
  reviews: readonly ReviewRoundRow[],
  taskId: string,
): ReviewRoundRow | undefined {
  return reviews
    .filter((round) => round.task_id === taskId)
    .sort((left, right) => right.round_number - left.round_number)[0];
}

export function buildProjectWorkInputs(
  options: ProjectWorkInputOptions,
): WorkTaskInput[] {
  return options.tasks
    .filter(
      (task) =>
        task.assignee_id === options.currentUserId ||
        options.isAcceptedCollaborator(task.id),
    )
    .map((task) => {
      const review = latestReview(options.reviews, task.id);
      const dependency = options.dependencyState?.(task.id) ?? {
        blocked: false,
      };
      const upstream = (options.upstreamTasks?.(task.id) ?? []).find(
        (candidate) => candidate.status !== "completed",
      );
      const responsibility =
        options.taskResponsibilityKind?.(task) ??
        (task.assignee_id === options.currentUserId
          ? "primary"
          : options.isAcceptedCollaborator(task.id)
            ? "collaborator"
            : null);

      return {
        task,
        projectId: options.projectId,
        projectName: options.projectName,
        responsibility:
          responsibility === "collaborator"
            ? { kind: "collaborator" as const }
            : {
                kind: "primary" as const,
                collaboratorCount: (
                  options.collaboratorsForTask?.(task.id) ?? []
                ).filter((item) => item.state === "accepted").length,
              },
        dependencyBlocked: dependency.blocked,
        upstreamTitle: upstream?.title ?? null,
        latestReviewDecision: review?.decision,
        latestReviewReason: review?.rejection_reason,
      };
    });
}

export function classifyWorkTask(input: WorkTaskInput): WorkTaskItem | null {
  const { task } = input;
  if (
    task.status === "canceled" ||
    task.assignment_state === "pending_acceptance"
  ) {
    return null;
  }

  const needsChanges = input.latestReviewDecision === "request_changes";
  const deadline = Date.parse(task.deadline_at);
  const now = Date.now();
  const overdue =
    Number.isFinite(deadline) &&
    deadline < now &&
    task.status !== "completed" &&
    task.status !== "canceled";
  const dueSoon =
    Number.isFinite(deadline) &&
    deadline >= now &&
    deadline <= now + 3 * DAY &&
    task.status !== "completed" &&
    task.status !== "canceled";

  let column: WorkBoardColumnId;
  let statusLabel: string;
  let statusDetail: string | undefined;

  if (task.status === "completed") {
    column = "completed";
    statusLabel = "已完成";
  } else if (input.dependencyBlocked && !task.first_submitted_at) {
    column = "blocked";
    statusLabel = "等待上游";
    statusDetail = input.upstreamTitle
      ? `上游：${input.upstreamTitle}`
      : "等待上游任务完成";
  } else if (task.status === "blocked") {
    column = "blocked";
    statusLabel = "阻塞";
    statusDetail = task.blocked_reason
      ? `原因：${task.blocked_reason}`
      : undefined;
  } else if (task.status === "not_started") {
    column = "not_started";
    statusLabel = "待开始";
  } else {
    column = "in_progress";
    if (needsChanges) {
      statusLabel = "需要修改";
      statusDetail = input.latestReviewReason
        ? `上次验收：${input.latestReviewReason}`
        : undefined;
    } else if (task.status === "awaiting_review") {
      statusLabel = "待验收";
      statusDetail = "已提交 · 等待他人验收";
    } else {
      statusLabel = "进行中";
    }
  }

  return {
    ...input,
    column,
    needsChanges,
    overdue,
    dueSoon,
    statusLabel,
    statusDetail,
  };
}

function priority(item: WorkTaskItem) {
  if (item.needsChanges) return 0;
  if (item.overdue) return 1;
  if (item.dueSoon) return 2;
  return 3;
}

export function sortWorkTasks(items: WorkTaskItem[]) {
  return [...items].sort((left, right) => {
    const priorityDiff = priority(left) - priority(right);
    if (priorityDiff) return priorityDiff;
    const deadlineDiff =
      Date.parse(left.task.deadline_at) - Date.parse(right.task.deadline_at);
    if (deadlineDiff) return deadlineDiff;
    return left.task.title.localeCompare(right.task.title, "zh-CN");
  });
}

export function buildWorkBoard(
  inputs: WorkTaskInput[],
  completedLimit = 5,
): WorkBoardModel {
  const classified = inputs
    .map(classifyWorkTask)
    .filter((item): item is WorkTaskItem => !!item);

  const completed = classified
    .filter((item) => item.column === "completed")
    .sort((left, right) => {
      const leftTime = Date.parse(
        left.task.completed_at ?? left.task.updated_at,
      );
      const rightTime = Date.parse(
        right.task.completed_at ?? right.task.updated_at,
      );
      return rightTime - leftTime;
    });

  return {
    columns: {
      not_started: sortWorkTasks(
        classified.filter((item) => item.column === "not_started"),
      ),
      in_progress: sortWorkTasks(
        classified.filter((item) => item.column === "in_progress"),
      ),
      blocked: sortWorkTasks(
        classified.filter((item) => item.column === "blocked"),
      ),
      completed: completed.slice(0, completedLimit),
    },
    completedTotal: completed.length,
  };
}
