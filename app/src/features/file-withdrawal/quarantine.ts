/**
 * Service-only Storage withdrawal phase 2. Do not bundle this module into browser
 * pages or inject the service_role secret through Vite. G provides the trusted
 * worker which supplies these operations and enforces the pending DB state.
 */
export interface PrivateWithdrawalIntent {
  readonly withdrawalId: string;
  readonly state: "pending_quarantine" | "withdrawn";
  readonly bucket: "teamup-files";
  readonly originalPath: string;
  readonly quarantinePath: string;
}
export interface StorageWithdrawalOps {
  exists(bucket: string, path: string): Promise<boolean>;
  move(
    bucket: string,
    sourcePath: string,
    destinationPath: string,
  ): Promise<void>;
  complete(withdrawalId: string): Promise<{ ok: boolean; state?: string }>;
}
export type WithdrawalOutcome = "already_withdrawn" | "quarantined";

export async function quarantineWithdrawnVersion(
  intent: PrivateWithdrawalIntent,
  ops: StorageWithdrawalOps,
): Promise<WithdrawalOutcome> {
  if (intent.state === "withdrawn") return "already_withdrawn";
  if (
    !intent.originalPath ||
    !intent.quarantinePath ||
    intent.originalPath === intent.quarantinePath ||
    !intent.quarantinePath.startsWith("quarantine/withdrawal/")
  ) {
    throw new Error("Invalid private withdrawal intent");
  }
  const [original, quarantined] = await Promise.all([
    ops.exists(intent.bucket, intent.originalPath),
    ops.exists(intent.bucket, intent.quarantinePath),
  ]);
  if (original && quarantined)
    throw new Error("Both storage locations present; fail closed");
  if (original && !quarantined) {
    // Supabase Storage MOVE changes the pathname. COPY is never acceptable.
    await ops.move(intent.bucket, intent.originalPath, intent.quarantinePath);
  } else if (!quarantined) {
    throw new Error(
      "Neither source nor quarantine exists; manual reconciliation required",
    );
  }
  const [originalAfter, quarantinedAfter] = await Promise.all([
    ops.exists(intent.bucket, intent.originalPath),
    ops.exists(intent.bucket, intent.quarantinePath),
  ]);
  if (originalAfter || !quarantinedAfter)
    throw new Error("Storage revocation not verified");
  // Database also checks storage.objects itself before emitting the event.
  const result = await ops.complete(intent.withdrawalId);
  if (!result.ok || result.state !== "withdrawn")
    throw new Error("Withdrawal completion failed");
  return "quarantined";
}
