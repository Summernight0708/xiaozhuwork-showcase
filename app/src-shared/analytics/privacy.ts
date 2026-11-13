export const OPS_MIN_COHORT_SIZE = 5;

export function isPrivateCohortSuppressed(sampleSize: number | null): boolean {
  return sampleSize !== null && sampleSize < OPS_MIN_COHORT_SIZE;
}

export function formatPrivateMetric(
  value: number,
  sampleSize: number | null,
): string {
  if (isPrivateCohortSuppressed(sampleSize)) return "<5";
  return Number.isFinite(value) ? String(value) : "—";
}

export function formatPrivateRate(
  rate: number | null,
  sampleSize: number | null,
): string {
  if (isPrivateCohortSuppressed(sampleSize)) return "<5";
  if (rate === null || !Number.isFinite(rate)) return "—";
  const percentage = Math.round(rate * 1000) / 10;
  return `${percentage}%`;
}
