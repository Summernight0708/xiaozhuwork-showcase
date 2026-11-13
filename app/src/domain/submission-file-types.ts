export const SUBMISSION_FILE_TYPES = [
  "pdf",
  "doc",
  "docx",
  "xlsx",
  "pptx",
  "csv",
  "txt",
  "md",
  "json",
  "xml",
  "css",
  "js",
  "ts",
  "png",
  "jpg",
  "gif",
  "webp",
] as const;

export type SubmissionFileType = (typeof SUBMISSION_FILE_TYPES)[number];

export function normalizeRequiredSubmissionFileTypes(
  values: readonly unknown[] | null | undefined,
): SubmissionFileType[] {
  const selected = new Set(values ?? []);
  return SUBMISSION_FILE_TYPES.filter((value) => selected.has(value));
}

export function isSubmissionFileType(
  value: unknown,
): value is SubmissionFileType {
  return (
    typeof value === "string" &&
    (SUBMISSION_FILE_TYPES as readonly string[]).includes(value)
  );
}

/**
 * The database requires submission file type arrays in the canonical
 * master-list order; re-sort any client-assembled list to match.
 */
export function sortSubmissionFileTypes(
  values: readonly SubmissionFileType[],
): SubmissionFileType[] {
  return [...values].sort(
    (a, b) =>
      SUBMISSION_FILE_TYPES.indexOf(a) - SUBMISSION_FILE_TYPES.indexOf(b),
  );
}

export const SUBMISSION_FILE_TYPE_OPTIONS: ReadonlyArray<{
  value: SubmissionFileType;
  label: string;
}> = SUBMISSION_FILE_TYPES.map((value) => ({
  value,
  label: value.toUpperCase(),
}));

const MIME_TO_SUBMISSION_FILE_TYPE: Readonly<
  Record<string, SubmissionFileType>
> = {
  "application/pdf": "pdf",
  "application/msword": "doc",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
    "docx",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation":
    "pptx",
  "text/csv": "csv",
  "text/plain": "txt",
  "text/markdown": "md",
  "application/json": "json",
  "application/xml": "xml",
  "text/xml": "xml",
  "text/css": "css",
  "text/javascript": "js",
  "application/javascript": "js",
  "text/typescript": "ts",
  "application/typescript": "ts",
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
};

export function submissionFileTypeFromMime(
  mimeType: string,
): SubmissionFileType | null {
  return MIME_TO_SUBMISSION_FILE_TYPE[mimeType.toLowerCase()] ?? null;
}

export function submissionFileTypeLabel(
  type: SubmissionFileType | null | undefined,
) {
  return type ? type.toUpperCase() : "";
}
