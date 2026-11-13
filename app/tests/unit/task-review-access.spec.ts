import { describe, expect, it } from "vitest";

import {
  canRequestChangesOnReview,
  canReviewTaskSubmission,
} from "@/domain/task-review";

const task = {
  created_by: "creator",
  assignee_id: "assignee",
};
const round = {
  state: "pending",
  submitted_by: "assignee",
};

describe("task review UX authorization", () => {
  it("allows the leader and task creator to review another assignee", () => {
    expect(
      canReviewTaskSubmission({
        role: "leader",
        currentUserId: "leader",
        task,
        round,
      }),
    ).toBe(true);
    expect(
      canReviewTaskSubmission({
        role: "member",
        currentUserId: "creator",
        task,
        round,
      }),
    ).toBe(true);
  });

  it("hides review actions from the assignee and unrelated members", () => {
    expect(
      canReviewTaskSubmission({
        role: "member",
        currentUserId: "assignee",
        task,
        round,
      }),
    ).toBe(false);
    expect(
      canReviewTaskSubmission({
        role: "member",
        currentUserId: "other",
        task,
        round,
      }),
    ).toBe(false);
  });

  it("allows only the independent reviewer delegated for this pending round", () => {
    const delegated = {
      ...round,
      delegation_required: true,
      delegated_reviewer_id: "other",
    };
    expect(
      canReviewTaskSubmission({
        role: "member",
        currentUserId: "other",
        task,
        round: delegated,
      }),
    ).toBe(true);
    expect(
      canReviewTaskSubmission({
        role: "member",
        currentUserId: "intruder",
        task,
        round: delegated,
      }),
    ).toBe(false);
    expect(
      canReviewTaskSubmission({
        role: "observer",
        currentUserId: "other",
        task,
        round: delegated,
      }),
    ).toBe(false);
    expect(
      canReviewTaskSubmission({
        role: "member",
        currentUserId: "assignee",
        task,
        round: { ...delegated, delegated_reviewer_id: "assignee" },
      }),
    ).toBe(false);
    expect(
      canReviewTaskSubmission({
        role: "member",
        currentUserId: "other",
        task,
        round: { ...delegated, delegation_required: false },
      }),
    ).toBe(false);
    expect(
      canReviewTaskSubmission({
        role: "member",
        currentUserId: "other",
        task,
        round: { ...delegated, state: "approved" },
      }),
    ).toBe(false);
  });

  it("gives only direct downstream owners reject-only authority", () => {
    const downstreamTasks = [
      {
        assignee_id: "downstream",
        assignment_state: "assigned",
        status: "in_progress",
      },
    ];
    const options = {
      role: "member" as const,
      currentUserId: "downstream",
      task,
      round,
      downstreamTasks,
    };
    expect(canReviewTaskSubmission(options)).toBe(false);
    expect(canRequestChangesOnReview(options)).toBe(true);
    expect(
      canRequestChangesOnReview({ ...options, currentUserId: "unrelated" }),
    ).toBe(false);
    expect(canRequestChangesOnReview({ ...options, role: "observer" })).toBe(
      false,
    );
    expect(
      canRequestChangesOnReview({ ...options, currentUserId: "assignee" }),
    ).toBe(false);
    expect(
      canRequestChangesOnReview({
        ...options,
        round: { ...round, state: "approved" },
      }),
    ).toBe(false);
    expect(
      canRequestChangesOnReview({
        ...options,
        downstreamTasks: [
          { ...downstreamTasks[0]!, assignment_state: "pending" },
        ],
      }),
    ).toBe(false);
  });

  it("does not expose actions for a non-pending round", () => {
    expect(
      canReviewTaskSubmission({
        role: "leader",
        currentUserId: "leader",
        task,
        round: { ...round, state: "approved" },
      }),
    ).toBe(false);
  });
});
