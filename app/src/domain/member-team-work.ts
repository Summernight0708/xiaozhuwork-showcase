export type MemberTimeRange = "week" | "month" | "all";

export interface MemberFlowMember {
  id: string;
  userId: string | null;
  displayName: string;
  roleLabel: string;
  joinedAt?: string;
  primaryCount: number;
  collaboratorCount: number;
}

export interface MemberFlowTask {
  id: string;
  title: string;
  primaryUserId: string | null;
  acceptedAt?: string | null;
  createdAt: string;
  deadlineAt: string;
  completedAt?: string | null;
  status: string;
  statusLabel: string;
  collaboratorCount?: number;
}

export interface TimelineWindow {
  start: number;
  end: number;
}

const DAY = 86_400_000;

function finiteDate(value: string | null | undefined) {
  const parsed = value ? Date.parse(value) : Number.NaN;
  return Number.isFinite(parsed) ? parsed : null;
}

export function memberPrimaryTasks(
  member: MemberFlowMember,
  tasks: MemberFlowTask[],
) {
  if (!member.userId) return [];
  return tasks.filter(
    (task) =>
      task.primaryUserId === member.userId && task.status !== "canceled",
  );
}

export function memberSwimlaneTasks(
  member: MemberFlowMember,
  tasks: MemberFlowTask[],
) {
  if (!member.userId) return [];
  return sortMemberTasks(
    tasks.filter((task) => task.primaryUserId === member.userId),
  );
}

export function sortMemberTasks(tasks: MemberFlowTask[]) {
  return [...tasks].sort((left, right) => {
    const leftDeadline = finiteDate(left.deadlineAt) ?? Number.MAX_SAFE_INTEGER;
    const rightDeadline =
      finiteDate(right.deadlineAt) ?? Number.MAX_SAFE_INTEGER;
    return (
      leftDeadline - rightDeadline ||
      left.title.localeCompare(right.title, "zh-CN") ||
      left.id.localeCompare(right.id, "zh-CN")
    );
  });
}

export function nextExpandedMemberId(
  currentMemberId: string | null,
  targetMemberId: string,
) {
  return currentMemberId === targetMemberId ? null : targetMemberId;
}

export function timelineWindow(
  range: MemberTimeRange,
  tasks: MemberFlowTask[],
  nowMs = Date.now(),
): TimelineWindow {
  const now = new Date(nowMs);
  if (range === "week") {
    const start = new Date(now);
    start.setHours(0, 0, 0, 0);
    const day = (start.getDay() + 6) % 7;
    start.setDate(start.getDate() - day);
    return { start: start.getTime(), end: start.getTime() + 7 * DAY };
  }
  if (range === "month") {
    const start = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
    const end = new Date(now.getFullYear(), now.getMonth() + 1, 1).getTime();
    return { start, end };
  }

  const dates = tasks
    .flatMap((task) => [
      finiteDate(task.acceptedAt) ?? finiteDate(task.createdAt),
      finiteDate(task.deadlineAt),
    ])
    .filter((value): value is number => value !== null);
  if (!dates.length) return { start: nowMs - 15 * DAY, end: nowMs + 15 * DAY };
  const min = Math.min(...dates);
  const max = Math.max(...dates);
  const padding = Math.max(DAY, (max - min) * 0.04);
  return { start: min - padding, end: Math.max(max + padding, min + DAY) };
}

export function taskTimelineStyle(
  task: MemberFlowTask,
  window: TimelineWindow,
) {
  const start =
    finiteDate(task.acceptedAt) ?? finiteDate(task.createdAt) ?? window.start;
  const end = finiteDate(task.deadlineAt) ?? start;
  const span = Math.max(window.end - window.start, DAY);
  const clippedStart = Math.max(window.start, Math.min(window.end, start));
  const clippedEnd = Math.max(clippedStart, Math.min(window.end, end));
  const left = ((clippedStart - window.start) / span) * 100;
  const width = Math.max(1.5, ((clippedEnd - clippedStart) / span) * 100);
  return {
    left: `${Math.max(0, Math.min(99, left))}%`,
    width: `${Math.min(100 - left, width)}%`,
  };
}

export function taskVerticalOffset(index: number) {
  return Math.min(index, 3) * 5;
}

export function visibleTaskGroups(
  tasks: MemberFlowTask[],
  expanded: boolean,
  showAllRemaining: boolean,
) {
  const sorted = sortMemberTasks(tasks);
  if (!expanded) {
    return { recent: [], remaining: sorted, fullyExpanded: false };
  }
  const recent = sorted.slice(0, 2);
  const remaining = sorted.slice(2);
  return {
    recent,
    remaining,
    fullyExpanded: showAllRemaining,
  };
}

export function taskInWindow(task: MemberFlowTask, window: TimelineWindow) {
  const start =
    finiteDate(task.acceptedAt) ?? finiteDate(task.createdAt) ?? window.start;
  const end = finiteDate(task.deadlineAt) ?? start;
  return end >= window.start && start <= window.end;
}
