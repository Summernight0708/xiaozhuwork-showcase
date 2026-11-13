import { describe, expect, it } from "vitest";

import {
  canManagePrimaryResponsibility,
  primaryHandoffCandidates,
} from "@/domain/task-primary-handoff";
import {
  canCorrectReviewRequestChanges,
  canReviewTaskSubmission,
} from "@/domain/task-review";
import { taskCreateErrorMessage } from "@/services/errors";

describe("task authority workflow domain rules", () => {
  const task = {
    id: "task-1",
    created_by: "creator-1",
    assignee_id: "primary-1",
    assignment_state: "assigned",
    status: "in_progress",
    first_submitted_at: null,
  };

  it("allows only the current primary to transfer or unassign before formal review history", () => {
    expect(
      canManagePrimaryResponsibility({
        currentUserId: "primary-1",
        task,
        hasReviewHistory: false,
        hasPendingTaskChange: false,
      }),
    ).toBe(true);
    expect(
      canManagePrimaryResponsibility({
        currentUserId: "member-2",
        task,
        hasReviewHistory: false,
        hasPendingTaskChange: false,
      }),
    ).toBe(false);
    expect(
      canManagePrimaryResponsibility({
        currentUserId: "primary-1",
        task: { ...task, first_submitted_at: "2026-10-04T00:00:00Z" },
        hasReviewHistory: true,
        hasPendingTaskChange: false,
      }),
    ).toBe(false);
    expect(
      canManagePrimaryResponsibility({
        currentUserId: "primary-1",
        task,
        hasReviewHistory: false,
        hasPendingTaskChange: true,
      }),
    ).toBe(false);
  });

  it("offers active non-observer members as handoff targets, including collaborators", () => {
    const candidates = primaryHandoffCandidates({
      currentPrimaryId: "primary-1",
      members: [
        {
          id: "m-primary",
          user_id: "primary-1",
          member_state: "active",
          role: "member",
          is_observer: false,
        },
        {
          id: "m-member",
          user_id: "member-2",
          member_state: "active",
          role: "member",
          is_observer: false,
        },
        {
          id: "m-admin",
          user_id: "admin-1",
          member_state: "active",
          role: "admin",
          is_observer: false,
        },
        {
          id: "m-observer",
          user_id: "observer-1",
          member_state: "active",
          role: "observer",
          is_observer: true,
        },
        {
          id: "m-removed",
          user_id: "removed-1",
          member_state: "removed",
          role: "member",
          is_observer: false,
        },
      ],
    });
    expect(candidates.map((member) => member.user_id)).toEqual([
      "member-2",
      "admin-1",
    ]);
  });

  it("allows only the reviewer who made the latest request-changes decision to open correction", () => {
    const rejectedRound = {
      id: "round-1",
      state: "rejected",
      decision: "request_changes",
      reviewed_by: "creator-1",
      submitted_by: "primary-1",
    };
    expect(
      canCorrectReviewRequestChanges({
        role: "member",
        currentUserId: "creator-1",
        task,
        round: rejectedRound,
        isLatestRound: true,
      }),
    ).toBe(true);
    expect(
      canCorrectReviewRequestChanges({
        role: "leader",
        currentUserId: "leader-1",
        task,
        round: rejectedRound,
        isLatestRound: true,
      }),
    ).toBe(false);
    expect(
      canCorrectReviewRequestChanges({
        role: "member",
        currentUserId: "creator-1",
        task,
        round: rejectedRound,
        isLatestRound: false,
      }),
    ).toBe(false);
    expect(
      canReviewTaskSubmission({
        role: "member",
        currentUserId: "creator-1",
        task,
        round: { ...rejectedRound, state: "pending" },
      }),
    ).toBe(true);
  });

  it("distinguishes task-create authority, stale state, validation, and target-member failures", () => {
    expect(
      taskCreateErrorMessage({
        ok: false,
        code: "NOT_FOUND_OR_NOT_AUTHORIZED",
        requestId: "r1",
        replayed: false,
      }),
    ).toContain("创建任务");
    expect(
      taskCreateErrorMessage({
        ok: false,
        code: "NOT_FOUND_OR_NOT_AUTHORIZED",
        field: "assigneeId",
        requestId: "r2",
        replayed: false,
      }),
    ).toContain("指派成员");
    expect(
      taskCreateErrorMessage({
        ok: false,
        code: "STALE_VERSION",
        requestId: "r3",
        replayed: false,
        currentVersion: 4,
      }),
    ).toContain("项目刚刚发生了变化");
    expect(
      taskCreateErrorMessage({
        ok: false,
        code: "VALIDATION_FAILED",
        field: "title",
        requestId: "r4",
        replayed: false,
      }),
    ).toContain("提交内容");
  });
});
