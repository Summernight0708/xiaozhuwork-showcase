export type TaskTimeErrorCode = "DDL_NOT_IN_FUTURE";

export type DeadlineValidation =
  { valid: true } | { valid: false; code: TaskTimeErrorCode };

export type PenaltyRatioInput = {
  startAt: string;
  deadlineAt: string;
  eventAt: string;
  kind: "late_submission" | "late_abandonment";
};

export type PenaltyRatioResult =
  { valid: true; ratio: number } | { valid: false; code: TaskTimeErrorCode };

const FREE_ABANDONMENT_WINDOW = 0.1;

function toEpochSeconds(value: string): number {
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) {
    throw new RangeError(`Invalid timestamp: ${value}`);
  }
  return Math.floor(milliseconds / 1000);
}

function toTimestamp(seconds: number): string {
  return new Date(seconds * 1000).toISOString();
}

export function resolveEffectiveStart(input: {
  acceptedAt: string | null;
  upstreamCompletedAt: (string | null)[];
}): string | null {
  if (input.upstreamCompletedAt.length > 0) {
    if (input.upstreamCompletedAt.some((completedAt) => completedAt === null)) {
      return null;
    }

    const latestUpstreamCompletion = Math.max(
      ...input.upstreamCompletedAt.map((completedAt) =>
        toEpochSeconds(completedAt!),
      ),
    );

    return toTimestamp(latestUpstreamCompletion);
  }

  return input.acceptedAt === null
    ? null
    : toTimestamp(toEpochSeconds(input.acceptedAt));
}

export function validateFutureDeadline(
  startAt: string,
  deadlineAt: string,
): DeadlineValidation {
  return toEpochSeconds(deadlineAt) > toEpochSeconds(startAt)
    ? { valid: true }
    : { valid: false, code: "DDL_NOT_IN_FUTURE" };
}

export function freeAbandonmentDeadline(
  startAt: string,
  deadlineAt: string,
): string {
  const start = toEpochSeconds(startAt);
  const deadline = toEpochSeconds(deadlineAt);
  const duration = deadline - start;

  if (duration <= 0) {
    throw new RangeError("Deadline must be after the effective start");
  }

  return toTimestamp(start + Math.floor(duration * FREE_ABANDONMENT_WINDOW));
}

export function calculatePenaltyRatio(
  input: PenaltyRatioInput,
): PenaltyRatioResult {
  const start = toEpochSeconds(input.startAt);
  const deadline = toEpochSeconds(input.deadlineAt);
  const event = toEpochSeconds(input.eventAt);
  const duration = deadline - start;

  if (duration <= 0) {
    return { valid: false, code: "DDL_NOT_IN_FUTURE" };
  }

  const numerator =
    input.kind === "late_submission"
      ? event - deadline
      : event - (start + Math.floor(duration * FREE_ABANDONMENT_WINDOW));

  return { valid: true, ratio: numerator / duration };
}
