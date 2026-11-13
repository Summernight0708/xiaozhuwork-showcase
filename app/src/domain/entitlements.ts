export type AccountPlan = "free" | "pro";

export type AccountEntitlementState =
  "free" | "scheduled" | "active" | "expired" | "cancelled";

export interface AccountEntitlement {
  plan: AccountPlan;
  state: AccountEntitlementState;
  startsAt: string | null;
  expiresAt: string | null;
  version: number;
}

export type ProjectEffectivePlan = "free" | "pro";
export type ProjectEntitlementState = "free" | "active" | "grace";
export type ProjectEntitlementSource =
  "none" | "account_member" | "project_grant" | "grace";

export interface ProjectEntitlement {
  projectId: string;
  plan: ProjectEffectivePlan;
  state: ProjectEntitlementState;
  source: ProjectEntitlementSource;
  graceExpiresAt: string | null;
}

function formatEntitlementDateTime(value: string | null) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

export function formatAccountEntitlement(entitlement: AccountEntitlement) {
  const startsAt = formatEntitlementDateTime(entitlement.startsAt);
  const expiresAt = formatEntitlementDateTime(entitlement.expiresAt);

  if (entitlement.state === "active") {
    return {
      label: "Pro",
      currentPlanLabel: "Pro",
      detail: expiresAt
        ? `当前有效方案为 Pro。有效期至 ${expiresAt}。`
        : "当前有效方案为 Pro。",
    };
  }

  if (entitlement.state === "scheduled") {
    return {
      label: "Pro 已安排",
      currentPlanLabel: "Free",
      detail: startsAt
        ? `当前有效方案为 Free。Pro 将于 ${startsAt} 生效。`
        : "当前有效方案为 Free。Pro 已安排，生效时间以账号状态为准。",
    };
  }

  if (entitlement.state === "expired") {
    return {
      label: "Pro 已到期",
      currentPlanLabel: "Free",
      detail: expiresAt
        ? `当前有效方案为 Free。Pro 已于 ${expiresAt} 到期。`
        : "当前有效方案为 Free。Pro 已到期。",
    };
  }

  if (entitlement.state === "cancelled") {
    return {
      label: "Pro 已取消",
      currentPlanLabel: "Free",
      detail: "当前有效方案为 Free。Pro 已取消。",
    };
  }

  return {
    label: "Free",
    currentPlanLabel: "Free",
    detail: "当前有效方案为 Free。",
  };
}

export function formatProjectEntitlement(entitlement: ProjectEntitlement) {
  if (entitlement.state === "grace") {
    return {
      label: "Pro · 宽限期",
      detail: "宽限结束后将按 Free 额度执行，现有数据不会被删除。",
      graceExpiryLabel: formatEntitlementDateTime(entitlement.graceExpiresAt),
      isPro: true,
      isGrace: true,
    };
  }

  if (entitlement.state === "active") {
    return {
      label: "Pro",
      detail:
        entitlement.source === "account_member"
          ? "由项目成员 Pro 提供。"
          : "由项目 Pro 权益提供。",
      graceExpiryLabel: null,
      isPro: true,
      isGrace: false,
    };
  }

  return {
    label: "Free",
    detail: "当前项目按 Free 权益运行。",
    graceExpiryLabel: null,
    isPro: false,
    isGrace: false,
  };
}
