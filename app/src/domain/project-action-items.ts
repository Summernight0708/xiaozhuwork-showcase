import type { RouteLocationRaw } from "vue-router";

import type { ProjectRole } from "@/domain/access-control";
import { canReviewTaskSubmission } from "@/domain/task-review";
import type {
  AssignmentOfferRow,
  ContributionConfirmationRow,
  JoinRequestRow,
  ReviewRoundRow,
  TaskCollaboratorRow,
  TaskRow,
} from "@/types/ui";

export type ProjectActionTarget =
  | { kind: "task"; taskId: string }
  | { kind: "review"; reviewRoundId: string }
  | { kind: "project-invitations" }
  | { kind: "project-contributions" };

export interface ProjectActionItem {
  id: string;
  title: string;
  detail?: string;
  kindLabel: string;
  target: ProjectActionTarget;
  createdAt?: string | null;
  deadlineAt?: string | null;
}

interface ContributionReportLike {
  state: string;
  reportId: string;
  version: number;
}

interface BuildProjectActionItemsOptions {
  projectId: string;
  currentUserId: string | null;
  role: ProjectRole;
  capabilities: {
    canReviewJoinRequest?: boolean;
    canConfirmContributionReport?: boolean;
  };
  tasks: readonly TaskRow[];
  assignmentOffers: readonly AssignmentOfferRow[];
  reviews: readonly ReviewRoundRow[];
  joinRequests: readonly JoinRequestRow[];
  contributionReport: ContributionReportLike | null;
  contributionConfirmations: readonly ContributionConfirmationRow[];
  findCollaborator: (taskId: string) => TaskCollaboratorRow | null | undefined;
}

function latestReview(
  reviews: readonly ReviewRoundRow[],
  taskId: string,
): ReviewRoundRow | undefined {
  return reviews
    .filter((round) => round.task_id === taskId)
    .sort((left, right) => right.round_number - left.round_number)[0];
}

export function buildProjectActionItems(
  options: BuildProjectActionItemsOptions,
): ProjectActionItem[] {
  const items: ProjectActionItem[] = [];
  const taskById = new Map(options.tasks.map((task) => [task.id, task]));

  for (const offer of options.assignmentOffers) {
    if (
      offer.state !== "pending" ||
      offer.target_user_id !== options.currentUserId
    ) {
      continue;
    }
    const task = taskById.get(offer.task_id);
    if (!task) continue;
    items.push({
      id: `assignment:${offer.id}`,
      title: task.title,
      kindLabel: "任务待接受",
      detail: "任务指派等待你接受或拒绝",
      target: { kind: "task", taskId: task.id },
      createdAt: offer.created_at,
      deadlineAt: task.deadline_at,
    });
  }

  for (const task of options.tasks) {
    const collaborator = options.findCollaborator(task.id);
    if (
      collaborator?.state !== "pending" ||
      collaborator.user_id !== options.currentUserId
    ) {
      continue;
    }
    items.push({
      id: `collaboration:${collaborator.id ?? task.id}`,
      title: task.title,
      kindLabel: "协作邀请",
      detail: "协作者邀请等待你接受或拒绝",
      target: { kind: "task", taskId: task.id },
      createdAt: collaborator.created_at,
      deadlineAt: task.deadline_at,
    });
  }

  for (const task of options.tasks) {
    const review = latestReview(options.reviews, task.id);
    if (
      task.assignee_id === options.currentUserId &&
      review?.decision === "request_changes"
    ) {
      items.push({
        id: `changes:${task.id}`,
        title: task.title,
        detail: review.rejection_reason ?? "验收要求修改后重新提交",
        kindLabel: "需要修改",
        target: { kind: "task", taskId: task.id },
        createdAt: review.created_at,
        deadlineAt: task.deadline_at,
      });
    }
  }

  for (const round of options.reviews) {
    const task = taskById.get(round.task_id);
    if (
      !task ||
      !canReviewTaskSubmission({
        role: options.role,
        currentUserId: options.currentUserId,
        task,
        round,
      })
    ) {
      continue;
    }
    items.push({
      id: `review:${round.id}`,
      title: `验收「${task.title}」`,
      detail: `第 ${round.round_number} 轮`,
      kindLabel: "验收",
      target: { kind: "review", reviewRoundId: round.id },
      createdAt: round.created_at,
    });
  }

  if (options.capabilities.canReviewJoinRequest) {
    for (const request of options.joinRequests) {
      if (request.state !== "pending") continue;
      items.push({
        id: `join:${request.id}`,
        title: "处理加入项目申请",
        detail: new Date(request.created_at).toLocaleString(),
        kindLabel: "加入申请",
        target: { kind: "project-invitations" },
        createdAt: request.created_at,
      });
    }
  }

  if (
    options.capabilities.canConfirmContributionReport &&
    options.contributionReport?.state === "draft" &&
    !options.contributionConfirmations.some(
      (confirmation) => confirmation.user_id === options.currentUserId,
    )
  ) {
    items.push({
      id: `report:${options.contributionReport.reportId}`,
      title: "确认贡献报告",
      detail: `报告 v${options.contributionReport.version} 等待你的确认`,
      kindLabel: "报告确认",
      target: { kind: "project-contributions" },
    });
  }

  return items;
}

export function projectActionRoute(
  target: ProjectActionTarget,
  projectId: string,
): RouteLocationRaw | null {
  if (target.kind === "task") return null;
  if (target.kind === "review") {
    return {
      name: "review-detail",
      params: { projectId, reviewRoundId: target.reviewRoundId },
    };
  }
  if (target.kind === "project-invitations") {
    return { name: "project-invitations", params: { projectId } };
  }
  return { name: "project-contributions", params: { projectId } };
}
