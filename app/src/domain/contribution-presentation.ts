import type {
  ContributionReportItem,
  MembershipRow,
  TaskRow,
} from "@/types/ui";

interface ContributionMemberLike {
  user_id: string | null;
  display_name_snapshot: string | null;
  is_observer: boolean;
  member_state: string;
  role: string;
}

interface ContributionTaskLike {
  id: string;
  assignee_id: string | null;
}

export interface MemberContributionPresentation {
  userId: string;
  displayName: string;
  role: string;
  primaryCompleted: number | null;
  collaboratorParticipated: number | null;
  contributionScore: number | null;
  items: ContributionReportItem[];
}

export function buildMemberContributionRows(options: {
  members: Array<MembershipRow | ContributionMemberLike>;
  tasks: Array<TaskRow | ContributionTaskLike>;
  items: ContributionReportItem[];
}): MemberContributionPresentation[] {
  const tasksById = new Map(options.tasks.map((task) => [task.id, task]));
  const anonymousItems = options.items.filter((item) => !item.memberUserId);

  const regularRows = options.members
    .filter(
      (member) =>
        member.member_state === "active" &&
        !member.is_observer &&
        typeof member.user_id === "string",
    )
    .map((member) => {
      const userId = member.user_id!;
      const items = options.items.filter(
        (item) => item.memberUserId === userId,
      );
      const matchedCompleted = new Set(
        items
          .filter((item) => tasksById.get(item.taskId)?.assignee_id === userId)
          .map((item) => item.taskId),
      ).size;
      const primaryCompleted =
        items.length === 0 && anonymousItems.length > 0
          ? null
          : matchedCompleted;
      const contributionScore =
        items.length > 0 &&
        items.every((item) => typeof item.contributionValue === "number")
          ? items.reduce(
              (total, item) => total + (item.contributionValue ?? 0),
              0,
            )
          : null;

      return {
        userId,
        displayName: member.display_name_snapshot?.trim() || "未命名成员",
        role: member.role,
        primaryCompleted,
        // Current main's contribution snapshot has one item per completed task,
        // attributed only to tasks.assignee_id. It cannot authoritatively prove
        // collaborator participation, so presentation must not infer a number.
        collaboratorParticipated: null,
        contributionScore,
        items,
      };
    });

  // F2 removes identity from project report entries for accounts undergoing
  // deletion. Never reconstruct their IDs from tasks or archived snapshots.
  // Preserve the signed contribution values in a non-attributable aggregate.
  if (anonymousItems.length === 0) return regularRows;

  const anonymousScore = anonymousItems.every(
    (item) => typeof item.contributionValue === "number",
  )
    ? anonymousItems.reduce(
        (total, item) => total + (item.contributionValue ?? 0),
        0,
      )
    : null;

  return [
    ...regularRows,
    {
      userId: "anonymous-contribution-aggregate",
      displayName: "匿名贡献（汇总）",
      role: "member",
      primaryCompleted: null,
      collaboratorParticipated: null,
      contributionScore: anonymousScore,
      items: anonymousItems,
    },
  ];
}
