import { describe, expect, it } from "vitest";

import {
  memberPrimaryTasks,
  memberSwimlaneTasks,
  nextExpandedMemberId,
  taskVerticalOffset,
  visibleTaskGroups,
  type MemberFlowMember,
  type MemberFlowTask,
} from "@/domain/member-team-work";
import {
  meaningfulWorkFacts,
  type MemberActivityEvent,
} from "@/domain/member-work-facts";

const member: MemberFlowMember = {
  id: "member-a",
  userId: "user-a",
  displayName: "张三",
  roleLabel: "成员",
  primaryCount: 4,
  collaboratorCount: 2,
};

function flowTask(id: string, primaryUserId = "user-a"): MemberFlowTask {
  return {
    id,
    title: id,
    primaryUserId,
    createdAt: "2026-10-01T00:00:00.000Z",
    acceptedAt: "2026-10-01T00:00:00.000Z",
    deadlineAt: `2026-10-${id.slice(-1).padStart(2, "0")}T00:00:00.000Z`,
    status: "in_progress",
    statusLabel: "进行中",
    collaboratorCount: 2,
  };
}

describe("member team work selectors", () => {
  it("renders tasks only on their primary assignee row", () => {
    const tasks = [flowTask("task-4"), flowTask("task-5", "user-b")];
    expect(memberPrimaryTasks(member, tasks).map((task) => task.id)).toEqual([
      "task-4",
    ]);
  });

  it("uses 5px overlap offsets capped after four visible layers", () => {
    expect([0, 1, 2, 3, 4, 5].map(taskVerticalOffset)).toEqual([
      0, 5, 10, 15, 15, 15,
    ]);
  });

  it("orders swimlane tasks strictly by nearest DDL and keeps canceled tasks visible", () => {
    const completed = {
      ...flowTask("task-3"),
      status: "completed",
      deadlineAt: "2026-10-03T00:00:00.000Z",
    };
    const canceled = {
      ...flowTask("task-8"),
      status: "canceled",
      deadlineAt: "2026-10-08T00:00:00.000Z",
    };
    const active = {
      ...flowTask("task-5"),
      deadlineAt: "2026-10-05T00:00:00.000Z",
    };

    expect(
      memberSwimlaneTasks(member, [canceled, active, completed]).map(
        (task) => task.id,
      ),
    ).toEqual(["task-3", "task-5", "task-8"]);
  });

  it("uses task id as the final deterministic tie-break for identical DDL and title", () => {
    const taskB = {
      ...flowTask("task-b"),
      title: "同名任务",
      deadlineAt: "2026-10-05T00:00:00.000Z",
    };
    const taskA = {
      ...flowTask("task-a"),
      title: "同名任务",
      deadlineAt: "2026-10-05T00:00:00.000Z",
    };

    expect(
      memberSwimlaneTasks(member, [taskB, taskA]).map((task) => task.id),
    ).toEqual(["task-a", "task-b"]);
  });

  it("keeps member expansion single-open and toggles the active lane closed", () => {
    expect(nextExpandedMemberId(null, "member-a")).toBe("member-a");
    expect(nextExpandedMemberId("member-a", "member-b")).toBe("member-b");
    expect(nextExpandedMemberId("member-a", "member-a")).toBeNull();
  });

  it("keeps the first two relevant tasks separate and stacks the rest", () => {
    const tasks = [1, 2, 3, 4, 5].map((index) => flowTask(`task-${index}`));
    const collapsed = visibleTaskGroups(tasks, false, false);
    expect(collapsed.recent).toHaveLength(0);
    expect(collapsed.remaining).toHaveLength(5);

    const expanded = visibleTaskGroups(tasks, true, false);
    expect(expanded.recent).toHaveLength(2);
    expect(expanded.remaining).toHaveLength(3);
    expect(expanded.fullyExpanded).toBe(false);

    expect(visibleTaskGroups(tasks, true, true).fullyExpanded).toBe(true);
  });

  it("filters preview, light binding and navigation out of work facts", () => {
    const base = {
      memberUserId: "user-a",
      taskId: "task-1",
      occurredAt: "2026-10-04T00:00:00.000Z",
      text: "event",
    };
    const events: MemberActivityEvent[] = [
      { ...base, id: "completion", kind: "task_completion" },
      { ...base, id: "submission", kind: "formal_submission" },
      { ...base, id: "review", kind: "approved_review" },
      { ...base, id: "collab", kind: "collaboration_joined" },
      { ...base, id: "help", kind: "help" },
      { ...base, id: "rework", kind: "rework" },
      { ...base, id: "preview", kind: "preview" },
      { ...base, id: "binding", kind: "light_binding" },
      { ...base, id: "nav", kind: "navigation" },
    ];
    expect(
      new Set(meaningfulWorkFacts(events).map((event) => event.id)),
    ).toEqual(
      new Set([
        "collab",
        "completion",
        "help",
        "rework",
        "review",
        "submission",
      ]),
    );
  });
});
