/** F0-only vocabulary: contracts, NOT deployed business features. */
export const FOLLOWUP_EVENT_TYPES = [
  "task_canceled",
  "task_responsibility_abandoned",
  "task_first_submitted_late",
  "project_archived",
  "project_restored",
  "project_retention_window_started",
  "file_version_withdrawn",
  "contribution_shares_proposed",
  "contribution_shares_confirmed",
  "contribution_penalty_assessed",
  "contribution_penalty_appealed",
  "contribution_penalty_adjusted",
] as const;
export type FollowupEventType = (typeof FOLLOWUP_EVENT_TYPES)[number];
export type FollowupProjectState =
  "active" | "archived" | "recovery_window" | "purged";
export type FollowupPenaltyCause =
  "task_responsibility_abandoned" | "task_first_submitted_late";
export interface FollowupEventSnapshot {
  schemaVersion: 1;
  occurrenceKey: string;
  responsibleUserId: string | null;
  occurredAt: string;
  aggregateVersion: number;
  policyVersion: 1;
}
export interface ResponsibilityTimingSnapshot extends FollowupEventSnapshot {
  taskId: string;
  responsibilityEpochId: string;
  effectiveStartAt: string;
  effectiveDeadlineAt: string;
  acceptedAt: string;
  freeAbandonUntil: string;
  blockedExempt: boolean;
  exemptionReason: string | null;
  acceptedExpectedContribution: string | null;
}
export interface FollowupCommandMeta {
  requestId: string;
  expectedVersion: number;
}
export const TASK_SHARE_TOTAL_BPS = 10_000;
/** UI preflight only; PostgreSQL must validate transactionally. */
export function hasExactTaskSharePool(
  allocations: readonly { memberId: string; shareBps: number }[],
): boolean {
  if (allocations.length === 0) return false;
  const seen = new Set<string>();
  let total = 0;
  for (const { memberId, shareBps } of allocations) {
    if (
      !memberId ||
      seen.has(memberId) ||
      !Number.isInteger(shareBps) ||
      shareBps <= 0 ||
      shareBps > TASK_SHARE_TOTAL_BPS
    )
      return false;
    seen.add(memberId);
    total += shareBps;
  }
  return total === TASK_SHARE_TOTAL_BPS;
}
/** Never penalize management cancellation, review delay, or reassignment. */
export function mayAutoAssessFollowupPenalty(options: {
  contributionMode: "weighted" | "facts_only";
  autoPenaltyEnabled: boolean;
  cause: FollowupEventType;
  blockedExempt: boolean;
}): boolean {
  return (
    options.contributionMode === "weighted" &&
    options.autoPenaltyEnabled &&
    !options.blockedExempt &&
    (options.cause === "task_responsibility_abandoned" ||
      options.cause === "task_first_submitted_late")
  );
}
