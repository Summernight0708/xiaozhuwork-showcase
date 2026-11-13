import type {
  FileRow,
  FileVersionRow,
  FinalFileDesignationRow,
  TaskRow,
} from "@/types/ui";
import type {
  UpstreamArtifactGroup,
  UpstreamArtifactPresentation,
} from "@/types/frontend-integration";

export function buildUpstreamArtifactGroups(input: {
  upstreamTasks: readonly TaskRow[];
  files: readonly FileRow[];
  versions: readonly FileVersionRow[];
  designations: readonly FinalFileDesignationRow[];
}): UpstreamArtifactGroup[] {
  const finalIds = new Set(
    input.designations
      .filter((designation) => designation.is_final)
      .map((designation) => designation.file_version_id),
  );

  return input.upstreamTasks.map((task) => {
    const artifacts: UpstreamArtifactPresentation[] = input.files
      .filter((file) => file.task_id === task.id)
      .flatMap((file) => {
        const versions = input.versions
          .filter((version) => version.file_id === file.id)
          .sort((a, b) => b.version_number - a.version_number);
        const formal = versions.find((version) => finalIds.has(version.id));
        if (!formal) return [];
        const latest = versions[0] ?? formal;
        return [
          {
            fileId: file.id,
            name: formal.original_name || file.logical_name,
            mimeType: formal.mime_type,
            versionId: formal.id,
            versionNumber: formal.version_number,
            latestVersionId: latest.id,
            latestVersionNumber: latest.version_number,
            binding: { kind: "none" as const },
          },
        ];
      });

    return {
      taskId: task.id,
      taskTitle: task.title,
      taskStatus: task.status,
      artifacts,
    };
  });
}
