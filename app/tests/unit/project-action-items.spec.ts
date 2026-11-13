import { describe, expect, it } from "vitest";

import { buildProjectActionItems } from "@/domain/project-action-items";
import type {
  AssignmentOfferRow,
  JoinRequestRow,
  ReviewRoundRow,
  TaskCollaboratorRow,
  TaskRow,
} from "@/types/ui";

function task(overrides: Partial<TaskRow> = {}): TaskRow {
  return {
    id: "task-1",
    project_id: "project-1",
    title: "任务",
    created_by: "leader",
    assignee_id: "user-2",
    deadline_at: "2026-10-10T00:00:00.000Z",
    status: "in_progress",
    assignment_state: "assigned",
    ...overrides,
  } as TaskRow;
}

describe("project action items", () => {
  it("reuses the six current-user action categories from ProjectTodos", () => {
    const tasks = [
      task({ id: "assignment", title: "任务指派" }),
      task({ id: "collaboration", title: "协作邀请" }),
      task({
        id: "changes",
        title: "需要修改",
        assignee_id: "user-1",
      }),
      task({
        id: "review",
        title: "待验收任务",
        created_by: "leader",
        assignee_id: "user-2",
      }),
    ];
    const reviews = [
      {
        id: "round-changes",
        task_id: "changes",
        round_number: 1,
        state: "completed",
        decision: "request_changes",
        rejection_reason: "补充原始数据",
        submitted_by: "user-1",
        created_at: "2026-10-03T00:00:00.000Z",
      },
      {
        id: "round-review",
        task_id: "review",
        round_number: 2,
        state: "pending",
        decision: null,
        rejection_reason: null,
        submitted_by: "user-2",
        created_at: "2026-10-04T00:00:00.000Z",
      },
    ] as ReviewRoundRow[];

    const items = buildProjectActionItems({
      projectId: "project-1",
      currentUserId: "user-1",
      role: "leader",
      capabilities: {
        canReviewJoinRequest: true,
        canConfirmContributionReport: true,
      },
      tasks,
      assignmentOffers: [
        {
          id: "offer-1",
          task_id: "assignment",
          target_user_id: "user-1",
          state: "pending",
          created_at: "2026-10-04T00:00:00.000Z",
        } as AssignmentOfferRow,
      ],
      reviews,
      joinRequests: [
        {
          id: "join-1",
          state: "pending",
          created_at: "2026-10-04T00:00:00.000Z",
        } as JoinRequestRow,
      ],
      contributionReport: {
        state: "draft",
        reportId: "report-1",
        version: 3,
      },
      contributionConfirmations: [],
      findCollaborator: (taskId) =>
        taskId === "collaboration"
          ? ({
              id: "collaborator-1",
              task_id: taskId,
              user_id: "user-1",
              state: "pending",
              created_at: "2026-10-04T00:00:00.000Z",
            } as TaskCollaboratorRow)
          : null,
    });

    expect(items.map((item) => item.kindLabel)).toEqual([
      "任务待接受",
      "协作邀请",
      "需要修改",
      "验收",
      "加入申请",
      "报告确认",
    ]);
    expect(items.find((item) => item.kindLabel === "验收")?.target).toEqual({
      kind: "review",
      reviewRoundId: "round-review",
    });
  });

  it("does not surface another user's pending assignment or collaboration", () => {
    const tasks = [task({ id: "task-1" })];

    const items = buildProjectActionItems({
      projectId: "project-1",
      currentUserId: "user-1",
      role: "member",
      capabilities: {},
      tasks,
      assignmentOffers: [
        {
          id: "offer-1",
          task_id: "task-1",
          target_user_id: "user-2",
          state: "pending",
          created_at: "2026-10-04T00:00:00.000Z",
        } as AssignmentOfferRow,
      ],
      reviews: [],
      joinRequests: [],
      contributionReport: null,
      contributionConfirmations: [],
      findCollaborator: () =>
        ({
          id: "collaborator-1",
          task_id: "task-1",
          user_id: "user-2",
          state: "pending",
          created_at: "2026-10-04T00:00:00.000Z",
        }) as TaskCollaboratorRow,
    });

    expect(items).toEqual([]);
  });
});
