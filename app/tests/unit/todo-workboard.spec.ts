import { describe, expect, it, vi } from "vitest";

import {
  buildWorkBoard,
  classifyWorkTask,
  sortWorkTasks,
  type WorkTaskInput,
} from "@/domain/todo-workboard";
import type { TaskRow } from "@/types/ui";

function task(overrides: Partial<TaskRow> = {}): TaskRow {
  return {
    id: "task-1",
    project_id: "project-1",
    title: "任务",
    description: null,
    created_by: "leader",
    assignee_id: "user-1",
    deadline_at: "2026-10-10T00:00:00.000Z",
    status: "in_progress",
    weight: 1,
    is_direct_assignment: false,
    accepted_at: "2026-10-01T00:00:00.000Z",
    first_submitted_at: null,
    completed_at: null,
    blocked_reason: null,
    version: 1,
    canceled_at: null,
    cancel_reason: null,
    created_at: "2026-10-01T00:00:00.000Z",
    updated_at: "2026-10-01T00:00:00.000Z",
    assignment_state: "assigned",
    required_submission_file_type: null,
    required_submission_file_types: [],
    requires_review: true,
    progress_text: null,
    ...overrides,
  };
}

function input(overrides: Partial<WorkTaskInput> = {}): WorkTaskInput {
  return {
    task: task(),
    projectId: "project-1",
    projectName: "课程调研",
    responsibility: { kind: "primary" },
    ...overrides,
  };
}

describe("todo work board", () => {
  it("keeps pending acceptance out of ordinary status columns", () => {
    expect(
      classifyWorkTask(
        input({ task: task({ assignment_state: "pending_acceptance" }) }),
      ),
    ).toBeNull();
  });

  it("keeps needs-changes tasks in progress with a distinct badge", () => {
    const item = classifyWorkTask(
      input({
        latestReviewDecision: "request_changes",
        latestReviewReason: "补充原始数据",
      }),
    );
    expect(item?.column).toBe("in_progress");
    expect(item?.statusLabel).toBe("需要修改");
    expect(item?.statusDetail).toContain("补充原始数据");
  });

  it("keeps submitter awaiting review in progress", () => {
    const item = classifyWorkTask(
      input({ task: task({ status: "awaiting_review" }) }),
    );
    expect(item?.column).toBe("in_progress");
    expect(item?.statusLabel).toBe("待验收");
  });

  it("distinguishes waiting-upstream from explicit blocked tasks", () => {
    const waiting = classifyWorkTask(
      input({ dependencyBlocked: true, upstreamTitle: "数据整理" }),
    );
    const blocked = classifyWorkTask(
      input({
        task: task({ status: "blocked", blocked_reason: "缺实验结果" }),
      }),
    );
    expect(waiting?.column).toBe("blocked");
    expect(waiting?.statusLabel).toBe("等待上游");
    expect(waiting?.statusDetail).toContain("数据整理");
    expect(blocked?.statusLabel).toBe("阻塞");
    expect(blocked?.statusDetail).toContain("缺实验结果");
  });

  it("does not override submitted or returned work with waiting-upstream status", () => {
    const reviewed = classifyWorkTask(
      input({
        dependencyBlocked: true,
        task: task({
          status: "awaiting_review",
          first_submitted_at: "2026-10-11T02:00:00Z",
        }),
      }),
    );
    const needsChanges = classifyWorkTask(
      input({
        dependencyBlocked: true,
        task: task({
          status: "in_progress",
          first_submitted_at: "2026-10-11T02:00:00Z",
        }),
        latestReviewDecision: "request_changes",
      }),
    );
    expect(reviewed?.column).toBe("in_progress");
    expect(reviewed?.statusLabel).toBe("待验收");
    expect(needsChanges?.column).toBe("in_progress");
    expect(needsChanges?.statusLabel).toBe("需要修改");
  });

  it("sorts needs changes, overdue, due soon, then ordinary by deadline", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-04T00:00:00.000Z"));
    const items = [
      classifyWorkTask(
        input({
          task: task({
            id: "ordinary",
            deadline_at: "2026-11-01T00:00:00.000Z",
          }),
        }),
      )!,
      classifyWorkTask(
        input({
          task: task({ id: "soon", deadline_at: "2026-10-05T00:00:00.000Z" }),
        }),
      )!,
      classifyWorkTask(
        input({
          task: task({ id: "late", deadline_at: "2026-10-03T00:00:00.000Z" }),
        }),
      )!,
      classifyWorkTask(
        input({
          task: task({ id: "changes" }),
          latestReviewDecision: "request_changes",
        }),
      )!,
    ];
    expect(sortWorkTasks(items).map((item) => item.task.id)).toEqual([
      "changes",
      "late",
      "soon",
      "ordinary",
    ]);
    vi.useRealTimers();
  });

  it("shows only five recent completed tasks while retaining total", () => {
    const completed = Array.from({ length: 7 }, (_, index) =>
      input({
        task: task({
          id: `done-${index}`,
          status: "completed",
          completed_at: `2026-10-0${index + 1}T00:00:00.000Z`,
        }),
      }),
    );
    const board = buildWorkBoard(completed);
    expect(board.completedTotal).toBe(7);
    expect(board.columns.completed).toHaveLength(5);
    expect(board.columns.completed[0]?.task.id).toBe("done-6");
  });

  it("preserves optional collaborator responsibility metadata", () => {
    const item = classifyWorkTask(
      input({ responsibility: { kind: "collaborator", collaboratorCount: 2 } }),
    );
    expect(item?.responsibility).toEqual({
      kind: "collaborator",
      collaboratorCount: 2,
    });
  });
});
