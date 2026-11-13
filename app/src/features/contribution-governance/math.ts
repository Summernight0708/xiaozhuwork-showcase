export interface ShareAllocation {
  userId: string;
  shareBps: number;
}

export interface CreditedShare extends ShareAllocation {
  amountUnits: bigint; // one unit = 0.0001 stars
}

export type PenaltyKind = "late" | "abandon";

/** Server is authoritative; this helper provides a deterministic UI preview. */
export function allocateContributionPool(
  poolUnits: bigint,
  allocations: ShareAllocation[],
): CreditedShare[] {
  if (poolUnits < 0n || allocations.length === 0)
    throw new Error("invalid contribution pool");
  const ids = new Set<string>();
  let sum = 0;
  for (const allocation of allocations) {
    if (
      !allocation.userId ||
      ids.has(allocation.userId) ||
      !Number.isInteger(allocation.shareBps) ||
      allocation.shareBps < 0 ||
      allocation.shareBps > 10000
    )
      throw new Error("invalid participant or share");
    ids.add(allocation.userId);
    sum += allocation.shareBps;
  }
  if (sum !== 10000)
    throw new Error("contribution shares must sum to 10000 bps");
  const result = allocations.map((item) => ({
    ...item,
    amountUnits: (poolUnits * BigInt(item.shareBps)) / 10000n,
  }));
  let remaining =
    poolUnits - result.reduce((acc, value) => acc + value.amountUnits, 0n);
  const order = [...result].sort((a, b) =>
    a.userId.localeCompare(b.userId, "en"),
  );
  for (const item of order) {
    if (remaining === 0n) break;
    item.amountUnits += 1n;
    remaining -= 1n;
  }
  return result;
}

export function penaltyRateBps(
  kind: PenaltyKind,
  delaySeconds: bigint,
  durationSeconds: bigint,
): number {
  if (durationSeconds <= 0n || delaySeconds <= 0n)
    throw new Error("invalid responsibility interval");
  if (delaySeconds * 10n <= durationSeconds)
    return kind === "late" ? 1000 : 2500;
  if (delaySeconds * 10n <= durationSeconds * 3n)
    return kind === "late" ? 2500 : 5000;
  if (delaySeconds * 10n <= durationSeconds * 6n)
    return kind === "late" ? 5000 : 7500;
  if (delaySeconds <= durationSeconds) return kind === "late" ? 7500 : 10000;
  return kind === "late" ? 10000 : 15000;
}

export function freeAbandonSeconds(durationSeconds: bigint): bigint {
  if (durationSeconds <= 0n) throw new Error("invalid responsibility interval");
  return durationSeconds / 10n;
}

export function penaltyAmountUnits(baseUnits: bigint, rateBps: number): bigint {
  if (
    baseUnits < 0n ||
    !Number.isInteger(rateBps) ||
    rateBps < 0 ||
    rateBps > 15000
  ) {
    throw new Error("invalid penalty");
  }
  return -((baseUnits * BigInt(rateBps) + 5000n) / 10000n);
}

export function formatUnits(units: bigint): string {
  const negative = units < 0n;
  const abs = negative ? -units : units;
  return `${negative ? "-" : ""}${abs / 10000n}.${String(abs % 10000n).padStart(4, "0")}`;
}
