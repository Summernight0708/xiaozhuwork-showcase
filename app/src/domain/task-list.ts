import type { TaskDependencyState } from "@/domain/task-display";
import type { TaskRow } from "@/types/ui";

export type TaskListStatusFilter =
  | "all"
  | "unclaimed"
  | "pending_acceptance"
  | "not_started"
  | "in_progress"
  | "waiting_upstream"
  | "blocked"
  | "awaiting_review"
  | "completed";

export interface TaskParticipantSnapshot {
  collaboratorUserIds?: readonly string[];
  acceptedCollaboratorUserIds?: readonly string[];
  collaboratorCount?: number;
}

export interface TaskListPresentation {
  status: Exclude<TaskListStatusFilter, "all" | "unclaimed">;
  alert: string | null;
  waitingUpstream: boolean;
  overdue: boolean;
}

export interface UnclaimedTaskCandidate {
  task: TaskRow;
  dependency: TaskDependencyState;
}

export function isUnclaimedTask(task: TaskRow): boolean {
  return (
    task.assignment_state === "claimable" &&
    !task.assignee_id &&
    task.status !== "completed" &&
    task.status !== "canceled"
  );
}

export function taskListPresentation(
  task: TaskRow,
  dependency: TaskDependencyState,
  nowMs = Date.now(),
): TaskListPresentation {
  const waitingUpstream =
    dependency.blocked &&
    !task.first_submitted_at &&
    task.status !== "completed" &&
    task.status !== "canceled";
  const overdue =
    task.status !== "completed" &&
    task.status !== "canceled" &&
    Number.isFinite(Date.parse(task.deadline_at)) &&
    Date.parse(task.deadline_at) < nowMs;

  if (task.status === "completed") {
    return {
      status: "completed",
      alert: null,
      waitingUpstream: false,
      overdue: false,
    };
  }

  if (task.assignment_state === "pending_acceptance") {
    return {
      status: "pending_acceptance",
      alert: overdue ? "已逾期" : null,
      waitingUpstream,
      overdue,
    };
  }

  if (waitingUpstream) {
    return {
      status: "waiting_upstream",
      alert:
        dependency.incompleteUpstreamCount > 0
          ? `等待 ${dependency.incompleteUpstreamCount} 个上游任务`
          : "等待上游",
      waitingUpstream: true,
      overdue,
    };
  }

  if (task.status === "blocked") {
    return {
      status: "blocked",
      alert: task.blocked_reason?.trim() || "任务当前阻塞",
      waitingUpstream: false,
      overdue,
    };
  }

  if (task.status === "awaiting_review") {
    return {
      status: "awaiting_review",
      alert: "待验收",
      waitingUpstream: false,
      overdue,
    };
  }

  if (task.status === "in_progress") {
    return {
      status: "in_progress",
      alert: overdue ? "已逾期" : null,
      waitingUpstream: false,
      overdue,
    };
  }

  return {
    status: "not_started",
    alert: overdue ? "已逾期" : null,
    waitingUpstream: false,
    overdue,
  };
}

export function matchesTaskListStatus(
  task: TaskRow,
  dependency: TaskDependencyState,
  filter: TaskListStatusFilter,
): boolean {
  if (filter === "all") return true;
  if (filter === "unclaimed") return isUnclaimedTask(task);
  return taskListPresentation(task, dependency).status === filter;
}

export function isTaskMine(
  task: TaskRow,
  currentUserId: string | null | undefined,
  participants: TaskParticipantSnapshot = {},
): boolean {
  if (!currentUserId) return false;
  if (task.assignee_id === currentUserId) return true;
  return (participants.acceptedCollaboratorUserIds ?? []).includes(
    currentUserId,
  );
}

export function compareUnclaimedTasks(
  left: UnclaimedTaskCandidate,
  right: UnclaimedTaskCandidate,
  nowMs = Date.now(),
): number {
  const leftDeadline = Date.parse(left.task.deadline_at);
  const rightDeadline = Date.parse(right.task.deadline_at);
  const leftOverdue = Number.isFinite(leftDeadline) && leftDeadline < nowMs;
  const rightOverdue = Number.isFinite(rightDeadline) && rightDeadline < nowMs;

  if (leftOverdue !== rightOverdue) return leftOverdue ? -1 : 1;

  if (leftDeadline !== rightDeadline) return leftDeadline - rightDeadline;

  const leftWeight = Math.max(
    1,
    Math.min(5, Math.round(left.task.weight || 1)),
  );
  const rightWeight = Math.max(
    1,
    Math.min(5, Math.round(right.task.weight || 1)),
  );
  if (leftWeight !== rightWeight) return rightWeight - leftWeight;

  return left.task.title.localeCompare(right.task.title, "zh-CN");
}

export function topUnclaimedTasks(
  candidates: readonly UnclaimedTaskCandidate[],
  limit = 5,
  nowMs = Date.now(),
): UnclaimedTaskCandidate[] {
  return [...candidates]
    .sort((left, right) => compareUnclaimedTasks(left, right, nowMs))
    .slice(0, Math.max(0, limit));
}
