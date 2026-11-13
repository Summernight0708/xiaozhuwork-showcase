interface PrimaryTaskLike {
  assignee_id: string | null;
  assignment_state: string;
  status: string;
  first_submitted_at: string | null;
}

interface HandoffMemberLike {
  user_id: string | null;
  member_state: string;
  role: string;
  is_observer: boolean;
}

export function canManagePrimaryResponsibility(options: {
  currentUserId: string | null;
  task: PrimaryTaskLike;
  hasReviewHistory: boolean;
  hasPendingTaskChange: boolean;
}) {
  const { currentUserId, task, hasReviewHistory, hasPendingTaskChange } =
    options;
  if (!currentUserId || task.assignee_id !== currentUserId) return false;
  if (task.assignment_state !== "assigned") return false;
  if (!["not_started", "in_progress", "blocked"].includes(task.status))
    return false;
  if (
    task.first_submitted_at !== null ||
    hasReviewHistory ||
    hasPendingTaskChange
  ) {
    return false;
  }
  return true;
}

export function primaryHandoffCandidates<T extends HandoffMemberLike>(options: {
  currentPrimaryId: string | null;
  members: readonly T[];
}) {
  return options.members.filter(
    (member) =>
      !!member.user_id &&
      member.user_id !== options.currentPrimaryId &&
      member.member_state === "active" &&
      member.role !== "observer" &&
      !member.is_observer,
  );
}
