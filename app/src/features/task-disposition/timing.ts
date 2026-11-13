/** Advisory UI math; authoritative clock and snapshots are PostgreSQL owned. */
export function freeAbandonUntilMs(
  effectiveStartMs: number,
  deadlineMs: number,
): number | null {
  if (!Number.isFinite(effectiveStartMs) || !Number.isFinite(deadlineMs))
    return null;
  const seconds = Math.floor((deadlineMs - effectiveStartMs) / 1000);
  if (seconds <= 0) return null;
  return effectiveStartMs + Math.floor(seconds * 0.1) * 1000;
}

export function lateFirstSubmission(
  firstSubmittedMs: number | null,
  deadlineMs: number,
  blockedExempt: boolean,
) {
  return (
    firstSubmittedMs !== null &&
    Number.isFinite(firstSubmittedMs) &&
    Number.isFinite(deadlineMs) &&
    !blockedExempt &&
    firstSubmittedMs > deadlineMs
  );
}
