import type { MembershipRow, ReviewRoundRow, TaskRow } from "@/types/ui";

export type MemberWorkFactKind =
  | "task_completion"
  | "formal_submission"
  | "approved_review"
  | "collaboration_joined"
  | "help"
  | "rework";

export type MemberActivityEvent = {
  id: string;
  memberUserId: string | null;
  taskId: string;
  occurredAt: string;
  kind: MemberWorkFactKind | "preview" | "light_binding" | "navigation";
  text: string;
};

export interface MemberWorkFact {
  id: string;
  taskId: string;
  occurredAt: string;
  kind: MemberWorkFactKind;
  text: string;
}

export interface MemberWorkSummary {
  memberId: string;
  userId: string | null;
  displayName: string;
  roleLabel: string;
  primaryCount: number;
  completedPrimaryCount: number;
  collaboratorCount: number;
  facts: MemberWorkFact[];
}

const meaningfulKinds = new Set<MemberWorkFactKind>([
  "task_completion",
  "formal_submission",
  "approved_review",
  "collaboration_joined",
  "help",
  "rework",
]);

export function meaningfulWorkFacts(events: MemberActivityEvent[]) {
  return events
    .filter(
      (event): event is MemberActivityEvent & { kind: MemberWorkFactKind } =>
        meaningfulKinds.has(event.kind as MemberWorkFactKind),
    )
    .map(({ id, taskId, occurredAt, kind, text }) => ({
      id,
      taskId,
      occurredAt,
      kind,
      text,
    }))
    .sort(
      (left, right) =>
        right.occurredAt.localeCompare(left.occurredAt) ||
        left.id.localeCompare(right.id),
    );
}

export function currentMemberActivityEvents(
  tasks: TaskRow[],
  reviews: ReviewRoundRow[],
): MemberActivityEvent[] {
  const taskById = new Map(tasks.map((task) => [task.id, task]));
  const events: MemberActivityEvent[] = [];

  for (const task of tasks) {
    if (task.status === "completed" && task.assignee_id) {
      events.push({
        id: `completion:${task.id}`,
        memberUserId: task.assignee_id,
        taskId: task.id,
        occurredAt: task.completed_at ?? task.updated_at,
        kind: "task_completion",
        text: `完成「${task.title}」`,
      });
    }
  }

  for (const review of reviews) {
    const task = taskById.get(review.task_id);
    if (!task) continue;
    if (review.submitted_by) {
      events.push({
        id: `submission:${review.id}`,
        memberUserId: review.submitted_by,
        taskId: review.task_id,
        occurredAt: review.submitted_at,
        kind: "formal_submission",
        text: `正式提交「${task.title}」第 ${review.round_number} 轮验收`,
      });
    }
    if (
      review.reviewed_by &&
      review.reviewed_at &&
      review.decision === "approve"
    ) {
      events.push({
        id: `review:${review.id}`,
        memberUserId: review.reviewed_by,
        taskId: review.task_id,
        occurredAt: review.reviewed_at,
        kind: "approved_review",
        text: `验收通过「${task.title}」`,
      });
    }
  }

  return events;
}

export function buildMemberWorkSummaries(input: {
  members: MembershipRow[];
  tasks: TaskRow[];
  reviews: ReviewRoundRow[];
  collaboratorTaskIdsByUserId?: Map<string, Set<string>>;
  extraEvents?: MemberActivityEvent[];
}): MemberWorkSummary[] {
  const events = [
    ...currentMemberActivityEvents(input.tasks, input.reviews),
    ...(input.extraEvents ?? []),
  ];

  return input.members
    .filter((member) => member.member_state === "active")
    .map((member) => {
      const primaryTasks = member.user_id
        ? input.tasks.filter(
            (task) =>
              task.assignee_id === member.user_id && task.status !== "canceled",
          )
        : [];
      const collaboratorCount = member.user_id
        ? (input.collaboratorTaskIdsByUserId?.get(member.user_id)?.size ?? 0)
        : 0;
      return {
        memberId: member.id,
        userId: member.user_id,
        displayName: member.display_name_snapshot?.trim() || "未命名成员",
        roleLabel:
          member.role === "leader"
            ? "组长"
            : member.role === "admin"
              ? "管理员"
              : member.is_observer
                ? "观察者"
                : "成员",
        primaryCount: primaryTasks.length,
        completedPrimaryCount: primaryTasks.filter(
          (task) => task.status === "completed",
        ).length,
        collaboratorCount,
        facts: meaningfulWorkFacts(
          events.filter((event) => event.memberUserId === member.user_id),
        ),
      };
    });
}
