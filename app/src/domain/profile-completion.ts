import type { ProfileRow } from "@/types/ui";

export function normalizeDisplayName(value: string) {
  return value.trim();
}

export function displayNameError(value: string) {
  const normalized = normalizeDisplayName(value);
  if (!normalized) return "请输入昵称。";
  if (normalized.length > 30) return "昵称最多 30 个字符。";
  return null;
}

export function profileNeedsCompletion(
  profile: Pick<ProfileRow, "display_name"> | null | undefined,
) {
  return !profile?.display_name?.trim();
}

export function safeReturnPath(value: unknown, fallback = "/projects") {
  return typeof value === "string" &&
    value.startsWith("/") &&
    !value.startsWith("//")
    ? value
    : fallback;
}

export function missingProjectIdentity(
  profile: Pick<ProfileRow, "real_name" | "student_number"> | null | undefined,
  requirements: {
    requireRealName: boolean;
    requireStudentNumber: boolean;
  },
) {
  return {
    realName: requirements.requireRealName && !profile?.real_name?.trim(),
    studentNumber:
      requirements.requireStudentNumber && !profile?.student_number?.trim(),
  };
}
