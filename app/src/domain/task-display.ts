export interface TaskDisplaySource {
  status: string;
  assignment_state: string;
  first_submitted_at?: string | null;
}

export interface TaskDependencySource {
  upstream_task_id: string;
  downstream_task_id: string;
}

export interface DependencyTaskSource {
  id: string;
  status: string;
  completed_at?: string | null;
}

export interface TaskDependencyState {
  blocked: boolean;
  upstreamCount: number;
  incompleteUpstreamCount: number;
  effectiveStartAt: string | null;
}

export function dependencyStateForTask(
  taskId: string,
  tasks: readonly DependencyTaskSource[],
  dependencies: readonly TaskDependencySource[],
): TaskDependencyState {
  const upstreamIds = dependencies
    .filter((dependency) => dependency.downstream_task_id === taskId)
    .map((dependency) => dependency.upstream_task_id);
  const byId = new Map(tasks.map((task) => [task.id, task]));
  const incompleteUpstreamCount = upstreamIds.filter(
    (upstreamId) => byId.get(upstreamId)?.status !== "completed",
  ).length;
  const completedAt = upstreamIds
    .map((upstreamId) => byId.get(upstreamId)?.completed_at ?? null)
    .filter((value): value is string => !!value);
  return {
    blocked: incompleteUpstreamCount > 0,
    upstreamCount: upstreamIds.length,
    incompleteUpstreamCount,
    effectiveStartAt:
      upstreamIds.length > 0 &&
      incompleteUpstreamCount === 0 &&
      completedAt.length === upstreamIds.length
        ? (completedAt.sort(
            (left, right) => Date.parse(right) - Date.parse(left),
          )[0] ?? null)
        : null,
  };
}

export function taskDisplayStatus(
  task: TaskDisplaySource,
  dependencyBlocked = false,
): string {
  if (task.status === "completed" || task.status === "canceled")
    return task.status;
  if (dependencyBlocked && !task.first_submitted_at) return "blocked";
  return task.assignment_state === "pending_acceptance"
    ? "pending_acceptance"
    : task.status;
}

export function taskNeedsAttention(
  task: TaskDisplaySource & { deadline_at: string },
  nowMs = Date.now(),
  dependencyBlocked = false,
) {
  if (task.status === "completed" || task.status === "canceled") return false;
  return (
    (dependencyBlocked && !task.first_submitted_at) ||
    task.status === "blocked" ||
    task.status === "awaiting_review" ||
    Date.parse(task.deadline_at) < nowMs
  );
}

export type TaskDeadlineFilter = "all" | "overdue" | "next7" | "later";

export function matchesTaskDeadline(
  filter: TaskDeadlineFilter | string,
  deadlineAt: string,
  status: string,
  nowMs = Date.now(),
): boolean {
  if (filter === "all") return true;
  if (status === "completed" || status === "canceled") return false;
  const deadline = Date.parse(deadlineAt);
  if (!Number.isFinite(deadline)) return false;
  if (filter === "overdue") return deadline < nowMs;
  const sevenDays = 7 * 86_400_000;
  if (filter === "next7")
    return deadline >= nowMs && deadline <= nowMs + sevenDays;
  if (filter === "later") return deadline > nowMs + sevenDays;
  return true;
}
