import type { ProjectRole } from "@/domain/access-control";

export function canActAsTaskParticipant(options: {
  role: ProjectRole;
  currentUserId: string | null;
  targetUserId: string | null | undefined;
}) {
  return (
    options.role !== "observer" &&
    !!options.currentUserId &&
    options.targetUserId === options.currentUserId
  );
}
