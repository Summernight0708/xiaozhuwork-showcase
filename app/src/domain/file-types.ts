export type ProjectFileType =
  | "pdf"
  | "presentation"
  | "word"
  | "spreadsheet"
  | "image"
  | "archive"
  | "other";

interface FileTypeSource {
  filename: string;
  mimeType: string;
}

function extensionOf(filename: string) {
  const index = filename.lastIndexOf(".");
  return index >= 0 ? filename.slice(index + 1).toLowerCase() : "";
}

export function projectFileType(source: FileTypeSource): ProjectFileType {
  const mime = source.mimeType.toLowerCase();
  const extension = extensionOf(source.filename);

  if (mime === "application/pdf" || extension === "pdf") return "pdf";
  if (
    mime.includes("presentation") ||
    mime.includes("powerpoint") ||
    extension === "ppt" ||
    extension === "pptx"
  ) {
    return "presentation";
  }
  if (
    mime.includes("word") ||
    mime.includes("msword") ||
    extension === "doc" ||
    extension === "docx"
  ) {
    return "word";
  }
  if (
    mime.includes("spreadsheet") ||
    mime.includes("excel") ||
    extension === "xls" ||
    extension === "xlsx"
  ) {
    return "spreadsheet";
  }
  if (mime.startsWith("image/")) return "image";
  if (
    mime.includes("zip") ||
    mime.includes("compressed") ||
    mime.includes("archive") ||
    ["zip", "rar", "7z", "tar", "gz"].includes(extension)
  ) {
    return "archive";
  }
  return "other";
}

export function matchesFileType(type: string, source: FileTypeSource) {
  return type === "all" || projectFileType(source) === type;
}

export type FileUpdatedWindow = "all" | "day" | "week" | "month";

export function matchesFileUploader(
  filter: string,
  uploadedBy?: string | null,
) {
  return filter === "all" || uploadedBy === filter;
}

export function matchesFileUpdatedWindow(
  filter: FileUpdatedWindow | string,
  updatedAt: string,
  nowMs = Date.now(),
) {
  if (filter === "all") return true;
  const updated = Date.parse(updatedAt);
  if (!Number.isFinite(updated)) return false;
  const age = nowMs - updated;
  if (age < 0) return false;
  const day = 86_400_000;
  if (filter === "day") return age <= day;
  if (filter === "week") return age <= 7 * day;
  if (filter === "month") return age <= 30 * day;
  return true;
}

export function fileWasUploadedBy(
  userId: string | null | undefined,
  createdBy: string | null | undefined,
  versions: ReadonlyArray<{ uploadedBy?: string | null }>,
) {
  if (!userId) return false;
  return (
    createdBy === userId ||
    versions.some((version) => version.uploadedBy === userId)
  );
}
