import type {
  FileRow,
  FileVersionRow,
  FinalFileDesignationRow,
  TaskRow,
} from "@/types/ui";
import type {
  ApprovedFileVersion,
  ApprovedProjectFile,
} from "@/types/frontend-integration";

export type ApprovedFileTypeFilter =
  "all" | "pdf" | "docx" | "xlsx" | "pptx" | "image" | "text" | "other";

export type ApprovedFileRangeFilter = "all" | "final";

function extensionOf(filename: string) {
  const index = filename.lastIndexOf(".");
  return index < 0 ? "" : filename.slice(index + 1).toLowerCase();
}

export function approvedFileType(
  filename: string,
  mimeType: string,
): Exclude<ApprovedFileTypeFilter, "all"> {
  const extension = extensionOf(filename);
  const mime = mimeType.toLowerCase();

  if (extension === "pdf" || mime === "application/pdf") return "pdf";
  if (
    extension === "docx" ||
    extension === "doc" ||
    mime.includes("wordprocessingml") ||
    mime.includes("msword")
  ) {
    return "docx";
  }
  if (
    ["xlsx", "xls", "csv"].includes(extension) ||
    mime.includes("spreadsheet") ||
    mime.includes("excel") ||
    mime === "text/csv"
  ) {
    return "xlsx";
  }
  if (
    ["pptx", "ppt"].includes(extension) ||
    mime.includes("presentationml") ||
    mime.includes("powerpoint")
  ) {
    return "pptx";
  }
  if (mime.startsWith("image/")) return "image";
  if (
    ["txt", "md", "json"].includes(extension) ||
    mime.startsWith("text/") ||
    mime === "application/json"
  ) {
    return "text";
  }
  return "other";
}

export function isPreviewSupported(filename: string, mimeType: string) {
  const extension = extensionOf(filename);
  const mime = mimeType.toLowerCase();
  return (
    [
      "png",
      "jpg",
      "jpeg",
      "webp",
      "gif",
      "pdf",
      "docx",
      "xlsx",
      "csv",
      "txt",
      "md",
      "json",
      "mp4",
    ].includes(extension) ||
    mime.startsWith("image/") ||
    mime === "application/pdf" ||
    mime === "application/json" ||
    mime === "text/plain" ||
    mime === "text/markdown" ||
    mime === "text/csv" ||
    mime === "video/mp4"
  );
}

export function sortImmutableVersions<T extends { versionNumber: number }>(
  versions: readonly T[],
) {
  return [...versions].sort((a, b) => b.versionNumber - a.versionNumber);
}

export function matchesApprovedProjectFile(
  file: ApprovedProjectFile,
  options: {
    search: string;
    type: ApprovedFileTypeFilter;
    range: ApprovedFileRangeFilter;
  },
) {
  const keyword = options.search.trim().toLowerCase();
  const current =
    file.versions.find((version) => version.id === file.currentVersionId) ??
    sortImmutableVersions(file.versions)[0] ??
    null;

  if (
    keyword &&
    !file.logicalName.toLowerCase().includes(keyword) &&
    !(current?.originalName ?? "").toLowerCase().includes(keyword)
  ) {
    return false;
  }
  if (options.range === "final" && file.finalVersionIds.length === 0)
    return false;
  if (
    options.type !== "all" &&
    (!current ||
      approvedFileType(current.originalName, current.mimeType) !== options.type)
  ) {
    return false;
  }
  return true;
}

export function buildApprovedProjectFiles(input: {
  files: readonly FileRow[];
  versions: readonly FileVersionRow[];
  designations: readonly FinalFileDesignationRow[];
  tasks: readonly TaskRow[];
  memberName: (userId?: string | null) => string;
}): ApprovedProjectFile[] {
  const taskById = new Map(input.tasks.map((task) => [task.id, task]));
  const finalIds = new Set(
    input.designations
      .filter((designation) => designation.is_final)
      .map((designation) => designation.file_version_id),
  );

  return input.files.map((file) => {
    const versions = input.versions
      .filter((version) => version.file_id === file.id)
      .map<ApprovedFileVersion>((version) => ({
        id: version.id,
        fileId: version.file_id,
        versionNumber: version.version_number,
        originalName: version.original_name,
        mimeType: version.mime_type,
        sizeBytes: version.size_bytes,
        objectPath: version.object_path,
        uploadedBy: version.uploaded_by,
        createdAt: version.created_at,
      }));

    const current = versions.find(
      (version) => version.id === file.current_version_id,
    );
    return {
      id: file.id,
      taskId: file.task_id,
      taskTitle: taskById.get(file.task_id)?.title ?? "任务",
      logicalName: file.logical_name,
      purpose: file.purpose === "reference" ? "reference" : "deliverable",
      currentVersionId: file.current_version_id,
      uploaderName: input.memberName(current?.uploadedBy ?? file.created_by),
      updatedAt: file.updated_at,
      finalVersionIds: versions
        .filter((version) => finalIds.has(version.id))
        .map((version) => version.id),
      versions,
    };
  });
}
