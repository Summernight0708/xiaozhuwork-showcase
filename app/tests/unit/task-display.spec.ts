import { describe, expect, it } from "vitest";

import {
  matchesTaskDeadline,
  taskDisplayStatus,
  taskNeedsAttention,
} from "@/domain/task-display";

describe("task display status", () => {
  it("uses assignment acceptance as the visible pending state", () => {
    expect(
      taskDisplayStatus({
        status: "not_started",
        assignment_state: "pending_acceptance",
      }),
    ).toBe("pending_acceptance");
  });

  it("preserves review and revision states once a dependent task has submitted", () => {
    const submitted = "2026-10-11T02:00:00Z";
    expect(
      taskDisplayStatus(
        {
          status: "awaiting_review",
          assignment_state: "assigned",
          first_submitted_at: submitted,
        },
        true,
      ),
    ).toBe("awaiting_review");
    expect(
      taskDisplayStatus(
        {
          status: "in_progress",
          assignment_state: "assigned",
          first_submitted_at: submitted,
        },
        true,
      ),
    ).toBe("in_progress");
    expect(
      taskDisplayStatus(
        {
          status: "in_progress",
          assignment_state: "assigned",
          first_submitted_at: null,
        },
        true,
      ),
    ).toBe("blocked");
  });

  it("filters tasks by overdue and upcoming DDL windows", () => {
    const now = Date.parse("2026-09-30T00:00:00Z");
    expect(
      matchesTaskDeadline(
        "overdue",
        "2026-09-29T23:59:59Z",
        "in_progress",
        now,
      ),
    ).toBe(true);
    expect(
      matchesTaskDeadline("overdue", "2026-09-29T23:59:59Z", "completed", now),
    ).toBe(false);
    expect(
      matchesTaskDeadline("next7", "2026-10-06T00:00:00Z", "in_progress", now),
    ).toBe(true);
    expect(
      matchesTaskDeadline("next7", "2026-10-08T00:00:00Z", "in_progress", now),
    ).toBe(false);
    expect(
      matchesTaskDeadline("all", "2026-10-08T00:00:00Z", "completed", now),
    ).toBe(true);
  });

  it("excludes terminal tasks from overdue filters and overview attention", () => {
    const now = Date.parse("2026-09-30T00:00:00Z");
    for (const status of ["completed", "canceled"]) {
      expect(
        matchesTaskDeadline("overdue", "2026-09-29T23:59:59Z", status, now),
      ).toBe(false);
      expect(
        taskNeedsAttention(
          {
            status,
            assignment_state: "assigned",
            deadline_at: "2026-09-29T23:59:59Z",
          },
          now,
        ),
      ).toBe(false);
    }
    expect(
      taskNeedsAttention(
        {
          status: "in_progress",
          assignment_state: "assigned",
          deadline_at: "2026-09-29T23:59:59Z",
        },
        now,
      ),
    ).toBe(true);
  });

  it("keeps backend not_started as the visible waiting-to-start state", () => {
    expect(
      taskDisplayStatus({
        status: "not_started",
        assignment_state: "claimable",
      }),
    ).toBe("not_started");
  });

  it("keeps the authoritative awaiting_review state", () => {
    expect(
      taskDisplayStatus({
        status: "awaiting_review",
        assignment_state: "assigned",
      }),
    ).toBe("awaiting_review");
  });
});
