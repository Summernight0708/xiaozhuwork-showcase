import { describe, expect, it } from "vitest";

import {
  compareUnclaimedTasks,
  isTaskMine,
  isUnclaimedTask,
  matchesTaskListStatus,
  taskListPresentation,
  topUnclaimedTasks,
} from "@/domain/task-list";
import type { TaskRow } from "@/types/ui";

function task(overrides: Partial<TaskRow> = {}): TaskRow {
  return {
    id: "task-1",
    project_id: "project-1",
    title: "数据分析",
    description: null,
    deadline_at: "2026-10-10T00:00:00Z",
    weight: 3,
    assignment_state: "assigned",
    required_submission_file_type: null,
    required_submission_file_types: [],
    requires_review: true,
    status: "in_progress",
    assignee_id: "user-1",
    accepted_at: "2026-10-01T00:00:00Z",
    blocked_reason: null,
    cancel_reason: null,
    canceled_at: null,
    completed_at: null,
    first_submitted_at: null,
    is_direct_assignment: false,
    progress_text: null,
    created_by: "leader-1",
    created_at: "2026-10-01T00:00:00Z",
    updated_at: "2026-10-01T00:00:00Z",
    version: 1,
    ...overrides,
  };
}

const ready = {
  blocked: false,
  upstreamCount: 0,
  incompleteUpstreamCount: 0,
  effectiveStartAt: null,
};

describe("task list presentation", () => {
  it("keeps waiting upstream distinct from a task's explicit blocked state", () => {
    const dependencyBlocked = {
      blocked: true,
      upstreamCount: 2,
      incompleteUpstreamCount: 1,
      effectiveStartAt: null,
    };

    expect(taskListPresentation(task(), dependencyBlocked)).toMatchObject({
      status: "waiting_upstream",
      alert: "等待 1 个上游任务",
    });
    expect(
      taskListPresentation(
        task({ status: "blocked", blocked_reason: "缺少实验数据" }),
        ready,
      ),
    ).toMatchObject({
      status: "blocked",
      alert: "缺少实验数据",
    });
  });

  it("stops showing dependency blocking after the first submission", () => {
    const dependencyBlocked = {
      blocked: true,
      upstreamCount: 1,
      incompleteUpstreamCount: 1,
      effectiveStartAt: null,
    };
    expect(
      taskListPresentation(
        task({
          status: "awaiting_review",
          first_submitted_at: "2026-10-11T02:00:00Z",
        }),
        dependencyBlocked,
      ),
    ).toMatchObject({ status: "awaiting_review", waitingUpstream: false });
    expect(
      taskListPresentation(
        task({
          status: "in_progress",
          first_submitted_at: "2026-10-11T02:00:00Z",
        }),
        dependencyBlocked,
      ),
    ).toMatchObject({ status: "in_progress", waitingUpstream: false });
  });

  it("recognizes only authoritative claimable tasks as unclaimed", () => {
    expect(
      isUnclaimedTask(
        task({
          assignment_state: "claimable",
          required_submission_file_type: null,
          assignee_id: null,
          status: "not_started",
        }),
      ),
    ).toBe(true);
    expect(
      isUnclaimedTask(
        task({
          assignment_state: "pending_acceptance",
          required_submission_file_type: null,
          assignee_id: null,
        }),
      ),
    ).toBe(false);
    expect(
      isUnclaimedTask(
        task({
          assignment_state: "claimable",
          required_submission_file_type: null,
          assignee_id: null,
          status: "completed",
        }),
      ),
    ).toBe(false);
  });

  it("treats mine as Primary plus accepted collaborators when participant data is available", () => {
    expect(isTaskMine(task(), "user-1")).toBe(true);
    expect(
      isTaskMine(task({ assignee_id: "primary-1" }), "user-2", {
        acceptedCollaboratorUserIds: ["user-2"],
      }),
    ).toBe(true);
    expect(isTaskMine(task({ assignee_id: "primary-1" }), "user-2")).toBe(
      false,
    );
  });

  it("filters waiting upstream without folding it into blocked", () => {
    const dependencyBlocked = {
      blocked: true,
      upstreamCount: 1,
      incompleteUpstreamCount: 1,
      effectiveStartAt: null,
    };
    expect(
      matchesTaskListStatus(task(), dependencyBlocked, "waiting_upstream"),
    ).toBe(true);
    expect(matchesTaskListStatus(task(), dependencyBlocked, "blocked")).toBe(
      false,
    );
  });
});

describe("unclaimed ordering", () => {
  const now = Date.parse("2026-10-04T00:00:00Z");

  it("orders overdue then nearest deadline, using task weight only as a secondary tie-break", () => {
    const overdue = task({
      id: "overdue",
      title: "逾期任务",
      assignment_state: "claimable",
      required_submission_file_type: null,
      assignee_id: null,
      deadline_at: "2026-10-03T00:00:00Z",
      weight: 1,
    });
    const soon = task({
      id: "soon",
      title: "即将到期",
      assignment_state: "claimable",
      required_submission_file_type: null,
      assignee_id: null,
      deadline_at: "2026-10-05T00:00:00Z",
      weight: 2,
    });
    const laterHigh = task({
      id: "later",
      title: "高星稍晚",
      assignment_state: "claimable",
      required_submission_file_type: null,
      assignee_id: null,
      deadline_at: "2026-10-06T00:00:00Z",
      weight: 5,
    });

    const candidates = [laterHigh, soon, overdue].map((item) => ({
      task: item,
      dependency: ready,
    }));
    expect(
      topUnclaimedTasks(candidates, 5, now).map((item) => item.task.id),
    ).toEqual(["overdue", "soon", "later"]);
    expect(
      compareUnclaimedTasks(candidates[1]!, candidates[2]!, now),
    ).toBeGreaterThan(0);
  });

  it("caps the default attention surface without mutating the source", () => {
    const candidates = Array.from({ length: 7 }, (_, index) => ({
      task: task({
        id: `task-${index}`,
        title: `Task ${index}`,
        assignment_state: "claimable",
        required_submission_file_type: null,
        assignee_id: null,
        deadline_at: `2026-10-${String(10 + index).padStart(2, "0")}T00:00:00Z`,
      }),
      dependency: ready,
    }));
    const visible = topUnclaimedTasks(candidates, 5, now);
    expect(visible).toHaveLength(5);
    expect(candidates).toHaveLength(7);
  });
});
