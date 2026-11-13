import { describe, expect, it } from "vitest";

import {
  canManageTaskCollaborators,
  isAcceptedCollaborator,
  isPrimaryAssignee,
  isTaskParticipant,
  taskResponsibilityKind,
} from "@/domain/task-participant";

const task = {
  id: "task-1",
  created_by: "creator-1",
  assignee_id: "primary-1",
};

const collaborators = [
  { task_id: "task-1", user_id: "collaborator-1", state: "accepted" },
  { task_id: "task-1", user_id: "pending-1", state: "pending" },
  { task_id: "task-1", user_id: "removed-1", state: "removed" },
  { task_id: "task-2", user_id: "other-task-1", state: "accepted" },
];

describe("task participant responsibility semantics", () => {
  it("keeps the primary assignee distinct from collaborators", () => {
    expect(isPrimaryAssignee(task, "primary-1")).toBe(true);
    expect(isPrimaryAssignee(task, "collaborator-1")).toBe(false);
    expect(
      isAcceptedCollaborator(collaborators, "task-1", "collaborator-1"),
    ).toBe(true);
    expect(isAcceptedCollaborator(collaborators, "task-1", "pending-1")).toBe(
      false,
    );
    expect(isAcceptedCollaborator(collaborators, "task-1", "removed-1")).toBe(
      false,
    );
  });

  it("treats only the primary and accepted collaborators as participants", () => {
    expect(isTaskParticipant(task, collaborators, "primary-1")).toBe(true);
    expect(isTaskParticipant(task, collaborators, "collaborator-1")).toBe(true);
    expect(isTaskParticipant(task, collaborators, "pending-1")).toBe(false);
    expect(isTaskParticipant(task, collaborators, "removed-1")).toBe(false);
    expect(isTaskParticipant(task, collaborators, "other-task-1")).toBe(false);
  });

  it("reports responsibility kind without promoting collaborators", () => {
    expect(taskResponsibilityKind(task, collaborators, "primary-1")).toBe(
      "primary",
    );
    expect(taskResponsibilityKind(task, collaborators, "collaborator-1")).toBe(
      "collaborator",
    );
    expect(taskResponsibilityKind(task, collaborators, "pending-1")).toBeNull();
  });

  it("lets only the task creator or leader manage collaborators", () => {
    expect(
      canManageTaskCollaborators({
        role: "member",
        currentUserId: "creator-1",
        task,
      }),
    ).toBe(true);
    expect(
      canManageTaskCollaborators({
        role: "leader",
        currentUserId: "leader-1",
        task,
      }),
    ).toBe(true);
    expect(
      canManageTaskCollaborators({
        role: "admin",
        currentUserId: "admin-1",
        task,
      }),
    ).toBe(false);
    expect(
      canManageTaskCollaborators({
        role: "member",
        currentUserId: "primary-1",
        task,
      }),
    ).toBe(false);
    expect(
      canManageTaskCollaborators({
        role: "observer",
        currentUserId: "creator-1",
        task,
      }),
    ).toBe(false);
  });
});
