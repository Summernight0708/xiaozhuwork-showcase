export const AUTH_PASSWORD_MIN_LENGTH = 8;
export const AUTH_VISIBLE_MIN_MS = 600;
export const AUTH_VISIBLE_JITTER_MS = 150;

export type NewPasswordValidation = "ok" | "too_short" | "mismatch";

export function validateNewPassword(
  password: string,
  confirmation: string,
): NewPasswordValidation {
  if (password.length < AUTH_PASSWORD_MIN_LENGTH) return "too_short";
  if (password !== confirmation) return "mismatch";
  return "ok";
}

export function visibleResponseDelayMs(
  startedAtMs: number,
  nowMs: number,
  random01 = Math.random(),
): number {
  const boundedRandom = Math.min(1, Math.max(0, random01));
  const jitter = Math.floor(AUTH_VISIBLE_JITTER_MS * boundedRandom);
  const target = AUTH_VISIBLE_MIN_MS + jitter;
  const elapsed = Math.max(0, nowMs - startedAtMs);
  return Math.max(0, target - elapsed);
}

export async function waitForVisibleResponseWindow(
  startedAtMs: number,
): Promise<void> {
  const delay = visibleResponseDelayMs(startedAtMs, Date.now());
  if (delay <= 0) return;
  await new Promise<void>((resolve) => {
    setTimeout(resolve, delay);
  });
}
