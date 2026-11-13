import type { ProjectRole } from "@/domain/access-control";

interface ReviewableTask {
  created_by: string | null;
  assignee_id: string | null;
}

interface ReviewRound {
  state: string;
  submitted_by: string | null;
  delegated_reviewer_id?: string | null;
  delegation_required?: boolean;
}

export function canReviewTaskSubmission(options: {
  role: ProjectRole;
  currentUserId: string | null;
  task: ReviewableTask;
  round: ReviewRound;
}) {
  const { role, currentUserId, task, round } = options;
  if (!currentUserId || round.state !== "pending") return false;
  if (
    task.assignee_id === currentUserId ||
    round.submitted_by === currentUserId
  ) {
    return false;
  }
  return (
    role === "leader" ||
    task.created_by === currentUserId ||
    (role !== "observer" &&
      round.delegation_required === true &&
      round.delegated_reviewer_id === currentUserId)
  );
}

// Direct downstream primary assignees may reject their upstream submission,
// but this must never grant them the ability to approve it.
export function canRequestChangesOnReview(options: {
  role: ProjectRole;
  currentUserId: string | null;
  task: ReviewableTask;
  round: ReviewRound;
  downstreamTasks: readonly {
    assignee_id: string | null;
    assignment_state: string;
    status: string;
  }[];
}) {
  if (canReviewTaskSubmission(options)) return true;
  const { role, currentUserId, task, round, downstreamTasks } = options;
  if (!currentUserId || role === "observer" || round.state !== "pending") {
    return false;
  }
  if (
    task.assignee_id === currentUserId ||
    round.submitted_by === currentUserId
  ) {
    return false;
  }
  return downstreamTasks.some(
    (downstream) =>
      downstream.assignee_id === currentUserId &&
      downstream.assignment_state === "assigned" &&
      downstream.status !== "canceled",
  );
}

interface CorrectableReviewRound extends ReviewRound {
  decision: string | null;
  reviewed_by: string | null;
}

export function canCorrectReviewRequestChanges(options: {
  role: ProjectRole;
  currentUserId: string | null;
  task: ReviewableTask;
  round: CorrectableReviewRound;
  isLatestRound: boolean;
}) {
  const { role, currentUserId, task, round, isLatestRound } = options;
  if (!currentUserId || !isLatestRound) return false;
  if (round.state !== "rejected" || round.decision !== "request_changes") {
    return false;
  }
  if (round.reviewed_by !== currentUserId) return false;
  if (
    task.assignee_id === currentUserId ||
    round.submitted_by === currentUserId
  ) {
    return false;
  }
  return role === "leader" || task.created_by === currentUserId;
}
