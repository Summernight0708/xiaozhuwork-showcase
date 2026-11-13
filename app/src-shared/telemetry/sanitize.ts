const UUID_PATTERN =
  /\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/i;
const EMAIL_PATTERN = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i;
const JWT_PATTERN = /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/;
const BEARER_PATTERN = /\bbearer\s+\S+/i;
const SENSITIVE_ASSIGNMENT_PATTERN =
  /\b(?:authorization|password|passcode|otp|token|access[_-]?token|refresh[_-]?token)\s*[:=]/i;

export function containsSensitiveTelemetryValue(value: unknown): boolean {
  if (typeof value === "string") {
    return (
      UUID_PATTERN.test(value) ||
      EMAIL_PATTERN.test(value) ||
      JWT_PATTERN.test(value) ||
      BEARER_PATTERN.test(value) ||
      SENSITIVE_ASSIGNMENT_PATTERN.test(value)
    );
  }

  if (Array.isArray(value)) {
    return value.some((entry) => containsSensitiveTelemetryValue(entry));
  }

  if (value && typeof value === "object") {
    return Object.entries(value as Record<string, unknown>).some(
      ([key, entry]) =>
        /^(?:authorization|password|otp|token|accessToken|refreshToken)$/i.test(
          key,
        ) || containsSensitiveTelemetryValue(entry),
    );
  }

  return false;
}

export function sanitizeUrl(rawUrl: string): string {
  let pathname: string;
  try {
    pathname = new URL(rawUrl, "https://telemetry.invalid").pathname;
  } catch {
    return "/other";
  }

  const sanitizedSegments = pathname.split("/").map((segment) => {
    if (!segment) return "";
    let decoded: string;
    try {
      decoded = decodeURIComponent(segment);
    } catch {
      return ":redacted";
    }
    if (UUID_PATTERN.test(decoded)) return ":id";
    if (containsSensitiveTelemetryValue(decoded)) return ":redacted";
    return segment;
  });

  const sanitized = sanitizedSegments.join("/");
  return sanitized.startsWith("/") ? sanitized : "/" + sanitized;
}
