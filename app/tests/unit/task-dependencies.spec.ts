import { describe, expect, it } from "vitest";
import {
  dependencyStateForTask,
  taskDisplayStatus,
} from "@/domain/task-display";

describe("task dependency display state", () => {
  const tasks = [
    { id: "a", status: "in_progress" },
    { id: "b", status: "completed" },
    { id: "c", status: "in_progress" },
  ];

  it("is blocked while any upstream is unfinished and unblocks when all are completed", () => {
    expect(
      dependencyStateForTask("c", tasks, [
        { upstream_task_id: "a", downstream_task_id: "c" },
        { upstream_task_id: "b", downstream_task_id: "c" },
      ]),
    ).toEqual({
      blocked: true,
      upstreamCount: 2,
      incompleteUpstreamCount: 1,
      effectiveStartAt: null,
    });
    expect(
      dependencyStateForTask(
        "c",
        tasks.map((task) => ({ ...task, status: "completed" })),
        [
          { upstream_task_id: "a", downstream_task_id: "c" },
          { upstream_task_id: "b", downstream_task_id: "c" },
        ],
      ),
    ).toEqual({
      blocked: false,
      upstreamCount: 2,
      incompleteUpstreamCount: 0,
      effectiveStartAt: null,
    });
  });

  it("uses the latest completion time as the multi-upstream effective start", () => {
    expect(
      dependencyStateForTask(
        "c",
        [
          {
            id: "a",
            status: "completed",
            completed_at: "2026-09-30T08:00:00Z",
          },
          {
            id: "b",
            status: "completed",
            completed_at: "2026-09-30T10:00:00Z",
          },
          { id: "c", status: "not_started" },
        ],
        [
          { upstream_task_id: "a", downstream_task_id: "c" },
          { upstream_task_id: "b", downstream_task_id: "c" },
        ],
      ).effectiveStartAt,
    ).toBe("2026-09-30T10:00:00Z");
  });

  it("dependency block takes display precedence without copying task.status", () => {
    expect(
      taskDisplayStatus(
        { status: "in_progress", assignment_state: "assigned" },
        true,
      ),
    ).toBe("blocked");
  });
});
