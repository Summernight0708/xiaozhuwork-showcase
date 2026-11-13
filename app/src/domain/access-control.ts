export type ProjectRole = "leader" | "admin" | "member" | "observer";

export interface RoleSource {
  role: string;
  isObserver: boolean;
}

export interface ProjectCapabilities {
  canCreateTask: boolean;
  canUploadFile: boolean;
  canReviewSubmission: boolean;
  canManageInvites: boolean;
  canReviewJoinRequest: boolean;
  canManageMembers: boolean;
  canUpdateProjectSettings: boolean;
  canMarkFinalFiles: boolean;
  canCreateContributionReport: boolean;
  canConfirmContributionReport: boolean;
}

export function normalizeProjectRole(source: RoleSource): ProjectRole {
  if (source.isObserver || source.role === "observer") return "observer";
  if (source.role === "leader") return "leader";
  if (source.role === "admin") return "admin";
  return "member";
}

export function capabilitiesForRole(
  role: ProjectRole,
  allowMemberTaskCreation = true,
): ProjectCapabilities {
  if (role === "observer") {
    return {
      canCreateTask: false,
      canUploadFile: false,
      canReviewSubmission: false,
      canManageInvites: false,
      canReviewJoinRequest: false,
      canManageMembers: false,
      canUpdateProjectSettings: false,
      canMarkFinalFiles: false,
      canCreateContributionReport: false,
      canConfirmContributionReport: false,
    };
  }

  if (role === "leader") {
    return {
      canCreateTask: true,
      canUploadFile: true,
      canReviewSubmission: true,
      canManageInvites: true,
      canReviewJoinRequest: true,
      canManageMembers: true,
      canUpdateProjectSettings: true,
      canMarkFinalFiles: true,
      canCreateContributionReport: true,
      canConfirmContributionReport: true,
    };
  }

  if (role === "admin") {
    return {
      canCreateTask: true,
      canUploadFile: true,
      canReviewSubmission: true,
      canManageInvites: false,
      canReviewJoinRequest: false,
      canManageMembers: true,
      canUpdateProjectSettings: false,
      canMarkFinalFiles: false,
      canCreateContributionReport: false,
      canConfirmContributionReport: true,
    };
  }

  return {
    canCreateTask: allowMemberTaskCreation,
    canUploadFile: true,
    canReviewSubmission: true,
    canManageInvites: false,
    canReviewJoinRequest: false,
    canManageMembers: false,
    canUpdateProjectSettings: false,
    canMarkFinalFiles: false,
    canCreateContributionReport: false,
    canConfirmContributionReport: true,
  };
}

export function capabilitiesForMembership(
  source: RoleSource | null | undefined,
  allowMemberTaskCreation = true,
): ProjectCapabilities {
  if (!source) return capabilitiesForRole("observer");
  return capabilitiesForRole(
    normalizeProjectRole(source),
    allowMemberTaskCreation,
  );
}

export const ROLE_LABELS: Record<ProjectRole, string> = {
  leader: "组长",
  admin: "管理员",
  member: "成员",
  observer: "观察者",
};
