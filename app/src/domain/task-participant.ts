import type { ProjectRole } from "@/domain/access-control";

export type TaskResponsibilityKind = "primary" | "collaborator";

export interface TaskResponsibilitySource {
  id: string;
  created_by: string | null;
  assignee_id: string | null;
}

export interface TaskCollaboratorSource {
  task_id: string;
  user_id: string | null;
  state: string;
}

export function isPrimaryAssignee(
  task: Pick<TaskResponsibilitySource, "assignee_id">,
  currentUserId: string | null | undefined,
) {
  return !!currentUserId && task.assignee_id === currentUserId;
}

export function isAcceptedCollaborator(
  collaborators: readonly TaskCollaboratorSource[],
  taskId: string,
  currentUserId: string | null | undefined,
) {
  return (
    !!currentUserId &&
    collaborators.some(
      (collaborator) =>
        collaborator.task_id === taskId &&
        collaborator.user_id === currentUserId &&
        collaborator.state === "accepted",
    )
  );
}

export function isTaskParticipant(
  task: Pick<TaskResponsibilitySource, "id" | "assignee_id">,
  collaborators: readonly TaskCollaboratorSource[],
  currentUserId: string | null | undefined,
) {
  return (
    isPrimaryAssignee(task, currentUserId) ||
    isAcceptedCollaborator(collaborators, task.id, currentUserId)
  );
}

export function taskResponsibilityKind(
  task: Pick<TaskResponsibilitySource, "id" | "assignee_id">,
  collaborators: readonly TaskCollaboratorSource[],
  currentUserId: string | null | undefined,
): TaskResponsibilityKind | null {
  if (isPrimaryAssignee(task, currentUserId)) return "primary";
  if (isAcceptedCollaborator(collaborators, task.id, currentUserId)) {
    return "collaborator";
  }
  return null;
}

export function canManageTaskCollaborators(options: {
  role: ProjectRole;
  currentUserId: string | null | undefined;
  task: Pick<TaskResponsibilitySource, "created_by">;
}) {
  if (!options.currentUserId || options.role === "observer") return false;
  return (
    options.role === "leader" ||
    options.task.created_by === options.currentUserId
  );
}
