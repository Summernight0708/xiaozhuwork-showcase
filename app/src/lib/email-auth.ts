import type {
  AuthError,
  Session,
  SupabaseClient,
  User,
} from "@supabase/supabase-js";

export type EmailAuthPort = Pick<
  SupabaseClient["auth"],
  | "signInWithOtp"
  | "verifyOtp"
  | "signInWithPassword"
  | "updateUser"
  | "signOut"
>;

export type EmailAuthErrorCode =
  | "INVALID_EMAIL"
  | "INVALID_CODE"
  | "INVALID_PASSWORD"
  | "INVALID_CREDENTIALS"
  | "RATE_LIMITED"
  | "PASSWORD_POLICY_REJECTED"
  | "AUTH_UNAVAILABLE";

export type EmailAuthResult =
  { ok: true } | { ok: false; code: EmailAuthErrorCode };

export type EmailVerificationResult =
  | { ok: false; code: EmailAuthErrorCode }
  | {
      ok: true;
      session: Session;
      user: User;
    };

export type PasswordUpdateResult =
  | { ok: false; code: EmailAuthErrorCode }
  | {
      ok: true;
      user: User;
    };

/* Supabase creates profiles via the auth.users trigger; callers only receive auth material. */
export type VerifiedEmailSession = {
  session: Session;
  user: User;
};

function normalizeEmail(email: string): string {
  return email.trim();
}

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function errorStatus(error: AuthError | null): number | undefined {
  if (!error) return undefined;
  const status = (error as AuthError & { status?: number }).status;
  return typeof status === "number" ? status : undefined;
}

function errorMessage(error: AuthError | null): string {
  return error?.message?.toLowerCase() ?? "";
}

function isRateLimited(error: AuthError | null): boolean {
  const message = errorMessage(error);
  return (
    errorStatus(error) === 429 ||
    message.includes("rate limit") ||
    message.includes("too many requests")
  );
}

async function requestOtp(
  auth: EmailAuthPort,
  inputEmail: string,
  shouldCreateUser: boolean,
): Promise<EmailAuthResult> {
  const email = normalizeEmail(inputEmail);
  if (!isValidEmail(email)) {
    return { ok: false, code: "INVALID_EMAIL" };
  }

  try {
    const { error } = await auth.signInWithOtp({
      email,
      options: { shouldCreateUser },
    });
    if (!error) return { ok: true };
    return {
      ok: false,
      code: isRateLimited(error) ? "RATE_LIMITED" : "AUTH_UNAVAILABLE",
    };
  } catch {
    return { ok: false, code: "AUTH_UNAVAILABLE" };
  }
}

export function requestSignupOtp(
  auth: EmailAuthPort,
  inputEmail: string,
): Promise<EmailAuthResult> {
  return requestOtp(auth, inputEmail, true);
}

export function requestRecoveryOtp(
  auth: EmailAuthPort,
  inputEmail: string,
): Promise<EmailAuthResult> {
  return requestOtp(auth, inputEmail, false);
}

/** @deprecated Use requestSignupOtp for registration. */
export function requestEmailCode(
  auth: EmailAuthPort,
  inputEmail: string,
): Promise<EmailAuthResult> {
  return requestSignupOtp(auth, inputEmail);
}

export async function verifyEmailOtp(
  auth: EmailAuthPort,
  inputEmail: string,
  inputCode: string,
): Promise<EmailVerificationResult> {
  const email = normalizeEmail(inputEmail);
  if (!isValidEmail(email)) {
    return { ok: false, code: "INVALID_EMAIL" };
  }

  const code = inputCode.trim();
  if (!/^\d{6}$/.test(code)) {
    return { ok: false, code: "INVALID_CODE" };
  }

  try {
    const { data, error } = await auth.verifyOtp({
      email,
      token: code,
      type: "email",
    });
    if (isRateLimited(error)) {
      return { ok: false, code: "RATE_LIMITED" };
    }
    if (error || !data.session || !data.user) {
      return { ok: false, code: "INVALID_CODE" };
    }
    return { ok: true, session: data.session, user: data.user };
  } catch {
    return { ok: false, code: "AUTH_UNAVAILABLE" };
  }
}

/** @deprecated Use verifyEmailOtp for registration/recovery. */
export function verifyEmailCode(
  auth: EmailAuthPort,
  inputEmail: string,
  inputCode: string,
): Promise<EmailVerificationResult> {
  return verifyEmailOtp(auth, inputEmail, inputCode);
}

export async function signInWithEmailPassword(
  auth: EmailAuthPort,
  inputEmail: string,
  password: string,
): Promise<EmailVerificationResult> {
  const email = normalizeEmail(inputEmail);
  if (!isValidEmail(email)) {
    return { ok: false, code: "INVALID_EMAIL" };
  }
  if (!password) {
    return { ok: false, code: "INVALID_PASSWORD" };
  }

  try {
    const { data, error } = await auth.signInWithPassword({ email, password });
    if (isRateLimited(error)) {
      return { ok: false, code: "RATE_LIMITED" };
    }
    if (error || !data.session || !data.user) {
      return { ok: false, code: "INVALID_CREDENTIALS" };
    }
    return { ok: true, session: data.session, user: data.user };
  } catch {
    return { ok: false, code: "AUTH_UNAVAILABLE" };
  }
}

export async function setAuthenticatedPassword(
  auth: EmailAuthPort,
  password: string,
): Promise<PasswordUpdateResult> {
  if (!password) {
    return { ok: false, code: "INVALID_PASSWORD" };
  }

  try {
    const { data, error } = await auth.updateUser({ password });
    if (isRateLimited(error)) {
      return { ok: false, code: "RATE_LIMITED" };
    }
    if (error) {
      const message = errorMessage(error);
      if (
        errorStatus(error) === 422 ||
        message.includes("password") ||
        message.includes("weak")
      ) {
        return { ok: false, code: "PASSWORD_POLICY_REJECTED" };
      }
      return { ok: false, code: "AUTH_UNAVAILABLE" };
    }
    if (!data.user) {
      return { ok: false, code: "AUTH_UNAVAILABLE" };
    }
    return { ok: true, user: data.user };
  } catch {
    return { ok: false, code: "AUTH_UNAVAILABLE" };
  }
}

export async function signOut(auth: EmailAuthPort): Promise<EmailAuthResult> {
  try {
    const { error } = await auth.signOut();
    return error ? { ok: false, code: "AUTH_UNAVAILABLE" } : { ok: true };
  } catch {
    return { ok: false, code: "AUTH_UNAVAILABLE" };
  }
}
