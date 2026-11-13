import { describe, expect, it } from "vitest";

import {
  buildMobileOverviewTodoItems,
  countMembersWithDueSoonTasks,
  summarizeMobileTaskFlow,
} from "@/domain/mobile-project-overview";
import {
  buildProjectWorkInputs,
  classifyWorkTask,
} from "@/domain/todo-workboard";
import type { MembershipRow, TaskDependencyRow, TaskRow } from "@/types/ui";

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
    progress_text: null,
    ...overrides,
  } as TaskRow;
}

function workItem(overrides: Partial<TaskRow> = {}, dependencyBlocked = false) {
  const value = classifyWorkTask({
    task: task(overrides),
    projectId: "project-1",
    projectName: "课程设计",
    responsibility: { kind: "primary" },
    dependencyBlocked,
  });
  if (!value) throw new Error("expected work item");
  return value;
}

describe("mobile project overview domain", () => {
  const nowMs = Date.parse("2026-10-04T00:00:00.000Z");

  it("ranks P1 explicit actions above P2 near deadlines above P3 ordinary work", () => {
    const items = buildMobileOverviewTodoItems({
      nowMs,
      limit: 10,
      actions: [
        {
          id: "review:1",
          title: "验收「接口实现」",
          detail: "第 2 轮",
          kindLabel: "验收",
          target: { kind: "review", reviewRoundId: "review-1" },
          createdAt: "2026-10-04T01:00:00.000Z",
        },
      ],
      workItems: [
        workItem({
          id: "ordinary",
          title: "普通任务",
          deadline_at: "2026-10-20T00:00:00.000Z",
        }),
        workItem({
          id: "soon",
          title: "临期任务",
          deadline_at: "2026-10-05T00:00:00.000Z",
        }),
      ],
    });

    expect(items.map((item) => item.title)).toEqual([
      "验收「接口实现」",
      "临期任务",
      "普通任务",
    ]);
    expect(items.map((item) => item.priority)).toEqual([1, 2, 3]);
  });

  it("uses the supplied clock instead of stale work-item deadline flags", () => {
    const stale = {
      ...workItem({
        id: "clocked",
        title: "按指定时钟判断",
        deadline_at: "2026-10-05T00:00:00.000Z",
      }),
      overdue: true,
      dueSoon: false,
    };

    const items = buildMobileOverviewTodoItems({
      nowMs,
      limit: 10,
      actions: [],
      workItems: [stale],
    });

    expect(items).toHaveLength(1);
    expect(items[0]?.priority).toBe(2);
    expect(items[0]?.reason).toBe("48 小时内截止");
  });

  it("orders overdue and blocked P1 work before near-deadline and later work", () => {
    const items = buildMobileOverviewTodoItems({
      nowMs,
      limit: 10,
      actions: [
        {
          id: "assignment:1",
          title: "等待接受",
          kindLabel: "任务待接受",
          target: { kind: "task", taskId: "assignment-task" },
          createdAt: "2026-10-04T00:00:00.000Z",
        },
      ],
      workItems: [
        workItem({
          id: "later",
          title: "稍后",
          deadline_at: "2026-10-20T00:00:00.000Z",
        }),
        workItem({
          id: "soon",
          title: "24 小时内",
          deadline_at: "2026-10-05T00:00:00.000Z",
        }),
        workItem(
          {
            id: "blocked",
            title: "等待上游",
            deadline_at: "2026-10-08T00:00:00.000Z",
          },
          true,
        ),
        workItem({
          id: "overdue",
          title: "已逾期",
          deadline_at: "2026-10-03T00:00:00.000Z",
        }),
      ],
    });

    expect(items.map((item) => item.title)).toEqual([
      "等待接受",
      "已逾期",
      "等待上游",
      "24 小时内",
      "稍后",
    ]);
  });

  it("returns at most three items and excludes completed work from ordinary todos", () => {
    const items = buildMobileOverviewTodoItems({
      nowMs,
      actions: [],
      workItems: [
        workItem({
          id: "completed",
          title: "已完成",
          status: "completed",
          deadline_at: "2026-10-02T00:00:00.000Z",
        }),
        {
          ...workItem({ id: "canceled-source" }),
          task: task({
            id: "canceled",
            title: "已取消",
            status: "canceled",
          }),
        },
        workItem({ id: "a", title: "A" }),
        workItem({
          id: "b",
          title: "B",
          deadline_at: "2026-10-11T00:00:00.000Z",
        }),
        workItem({
          id: "c",
          title: "C",
          deadline_at: "2026-10-12T00:00:00.000Z",
        }),
        workItem({
          id: "d",
          title: "D",
          deadline_at: "2026-10-13T00:00:00.000Z",
        }),
      ],
    });

    expect(items).toHaveLength(3);
    expect(items.some((item) => item.title === "已完成")).toBe(false);
    expect(items.some((item) => item.title === "已取消")).toBe(false);
  });

  it("scopes ordinary work to the current user plus accepted collaborations", () => {
    const tasks = [
      task({
        id: "mine",
        title: "我的逾期任务",
        assignee_id: "user-1",
        deadline_at: "2026-10-03T00:00:00.000Z",
      }),
      task({
        id: "other",
        title: "他人的逾期任务",
        assignee_id: "user-2",
        deadline_at: "2026-10-02T00:00:00.000Z",
      }),
      task({
        id: "collab",
        title: "我参与的协作任务",
        assignee_id: "user-2",
      }),
    ];

    const inputs = buildProjectWorkInputs({
      tasks,
      reviews: [],
      projectId: "project-1",
      projectName: "课程设计",
      currentUserId: "user-1",
      isAcceptedCollaborator: (taskId) => taskId === "collab",
    });

    expect(inputs.map((item) => item.task.id)).toEqual(["mine", "collab"]);
  });

  it("summarizes completion, DAG stages and unique blocked tasks", () => {
    const tasks = [
      task({ id: "a", status: "completed" }),
      task({ id: "b", status: "blocked" }),
      task({ id: "c", status: "in_progress" }),
      task({ id: "d", status: "canceled" }),
    ];
    const dependencies = [
      { upstream_task_id: "a", downstream_task_id: "b" },
      { upstream_task_id: "b", downstream_task_id: "c" },
    ] as TaskDependencyRow[];

    const summary = summarizeMobileTaskFlow(
      tasks,
      dependencies,
      (taskId) => taskId === "b" || taskId === "c",
    );

    expect(summary).toEqual({
      completed: 1,
      total: 3,
      stages: 3,
      blocked: 2,
    });
  });

  it("counts members with due-soon primary tasks only once", () => {
    const members = [
      { user_id: "user-1" },
      { user_id: "user-2" },
    ] as MembershipRow[];
    const tasks = [
      task({
        id: "soon-1",
        assignee_id: "user-1",
        deadline_at: "2026-10-05T00:00:00.000Z",
      }),
      task({
        id: "soon-2",
        assignee_id: "user-1",
        deadline_at: "2026-10-06T00:00:00.000Z",
      }),
      task({
        id: "later",
        assignee_id: "user-2",
        deadline_at: "2026-10-10T00:00:00.000Z",
      }),
    ];

    expect(countMembersWithDueSoonTasks(tasks, members, nowMs)).toBe(1);
  });
});
