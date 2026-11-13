import { buildTaskGraph } from "@/domain/task-dependency-graph";
import type {
  ProjectActionItem,
  ProjectActionTarget,
} from "@/domain/project-action-items";
import type { WorkTaskItem } from "@/domain/todo-workboard";
import type { MembershipRow, TaskDependencyRow, TaskRow } from "@/types/ui";

const HOUR = 3_600_000;
const DAY = 86_400_000;

export interface MobileOverviewTodoItem {
  id: string;
  title: string;
  reason: string;
  detail?: string;
  deadlineAt?: string | null;
  priority: 1 | 2 | 3;
  target: ProjectActionTarget;
}

export interface MobileTaskFlowSummary {
  completed: number;
  total: number;
  stages: number;
  blocked: number;
}

interface MobileTodoOptions {
  actions: readonly ProjectActionItem[];
  workItems: readonly WorkTaskItem[];
  nowMs?: number;
  limit?: number;
}

function finiteTime(value: string | null | undefined) {
  if (!value) return Number.POSITIVE_INFINITY;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : Number.POSITIVE_INFINITY;
}

function actionReason(kindLabel: string) {
  switch (kindLabel) {
    case "任务待接受":
      return "等待你接受任务";
    case "协作邀请":
      return "等待你处理协作邀请";
    case "需要修改":
      return "需要修改并重新提交";
    case "验收":
      return "等待你验收";
    case "加入申请":
      return "等待你处理加入申请";
    case "报告确认":
      return "等待你确认贡献报告";
    default:
      return kindLabel;
  }
}

function actionDetail(action: ProjectActionItem) {
  if (action.kindLabel === "任务待接受" || action.kindLabel === "协作邀请") {
    return undefined;
  }
  return action.detail;
}

export function buildMobileOverviewTodoItems({
  actions,
  workItems,
  nowMs = Date.now(),
  limit = 3,
}: MobileTodoOptions): MobileOverviewTodoItem[] {
  const taskWorkItem = new Map(
    workItems.map((item) => [item.task.id, item] as const),
  );
  const explicitTaskIds = new Set(
    actions
      .filter(
        (
          action,
        ): action is ProjectActionItem & {
          target: { kind: "task"; taskId: string };
        } => action.target.kind === "task",
      )
      .map((action) => action.target.taskId),
  );

  const ranked: Array<
    MobileOverviewTodoItem & { bucket: number; sortAt: number }
  > = actions.map((action) => {
    const task =
      action.target.kind === "task"
        ? taskWorkItem.get(action.target.taskId)?.task
        : undefined;
    return {
      id: action.id,
      title: action.title,
      reason: actionReason(action.kindLabel),
      detail: actionDetail(action),
      deadlineAt: action.deadlineAt ?? task?.deadline_at ?? null,
      priority: 1,
      target: action.target,
      bucket: 0,
      sortAt: Math.min(
        finiteTime(action.deadlineAt ?? task?.deadline_at),
        finiteTime(action.createdAt),
      ),
    };
  });

  for (const item of workItems) {
    if (
      item.task.status === "completed" ||
      item.task.status === "canceled" ||
      explicitTaskIds.has(item.task.id)
    ) {
      continue;
    }

    const deadline = finiteTime(item.task.deadline_at);
    const target: ProjectActionTarget = {
      kind: "task",
      taskId: item.task.id,
    };

    if (deadline < nowMs) {
      ranked.push({
        id: `task:${item.task.id}`,
        title: item.task.title,
        reason: "已逾期",
        deadlineAt: item.task.deadline_at,
        priority: 1,
        target,
        bucket: 1,
        sortAt: deadline,
      });
      continue;
    }

    if (item.column === "blocked") {
      ranked.push({
        id: `task:${item.task.id}`,
        title: item.task.title,
        reason: item.statusLabel,
        detail: item.statusDetail,
        deadlineAt: item.task.deadline_at,
        priority: 1,
        target,
        bucket: 2,
        sortAt: deadline,
      });
      continue;
    }

    if (deadline >= nowMs && deadline <= nowMs + 48 * HOUR) {
      ranked.push({
        id: `task:${item.task.id}`,
        title: item.task.title,
        reason: "48 小时内截止",
        deadlineAt: item.task.deadline_at,
        priority: 2,
        target,
        bucket: 0,
        sortAt: deadline,
      });
      continue;
    }

    ranked.push({
      id: `task:${item.task.id}`,
      title: item.task.title,
      reason: item.statusLabel,
      deadlineAt: item.task.deadline_at,
      priority: 3,
      target,
      bucket: 0,
      sortAt: deadline,
    });
  }

  return ranked
    .sort((left, right) => {
      const priorityDiff = left.priority - right.priority;
      if (priorityDiff) return priorityDiff;
      const bucketDiff = left.bucket - right.bucket;
      if (bucketDiff) return bucketDiff;
      if (left.sortAt !== right.sortAt) {
        return left.sortAt < right.sortAt ? -1 : 1;
      }
      return left.id.localeCompare(right.id, "zh-CN");
    })
    .slice(0, Math.max(0, limit))
    .map((item) => ({
      id: item.id,
      title: item.title,
      reason: item.reason,
      detail: item.detail,
      deadlineAt: item.deadlineAt,
      priority: item.priority,
      target: item.target,
    }));
}

export function summarizeMobileTaskFlow(
  tasks: readonly TaskRow[],
  dependencies: readonly TaskDependencyRow[],
  dependencyBlocked: (taskId: string) => boolean,
): MobileTaskFlowSummary {
  const activeTasks = tasks.filter((task) => task.status !== "canceled");
  const graph = buildTaskGraph(activeTasks, dependencies);
  const stages = new Set(graph.nodes.map((node) => node.rank)).size;
  const blocked = activeTasks.filter(
    (task) =>
      task.status !== "completed" &&
      (task.status === "blocked" || dependencyBlocked(task.id)),
  ).length;

  return {
    completed: activeTasks.filter((task) => task.status === "completed").length,
    total: activeTasks.length,
    stages,
    blocked,
  };
}

export function countMembersWithDueSoonTasks(
  tasks: readonly TaskRow[],
  members: readonly MembershipRow[],
  nowMs = Date.now(),
) {
  const memberIds = new Set(
    members
      .map((member) => member.user_id)
      .filter((userId): userId is string => Boolean(userId)),
  );
  const dueSoonMembers = new Set<string>();

  for (const task of tasks) {
    if (
      !task.assignee_id ||
      !memberIds.has(task.assignee_id) ||
      task.status === "completed" ||
      task.status === "canceled"
    ) {
      continue;
    }
    const deadline = finiteTime(task.deadline_at);
    if (deadline >= nowMs && deadline <= nowMs + 3 * DAY) {
      dueSoonMembers.add(task.assignee_id);
    }
  }

  return dueSoonMembers.size;
}
