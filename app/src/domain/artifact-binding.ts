export type ArtifactBindingStrength = "light" | "strong";

export interface FormalArtifactVersion {
  fileVersionId: string;
  versionNumber: number;
  objectPath: string;
  originalName: string;
  mimeType: string;
  sizeBytes: number;
  createdAt: string;
}

export interface ArtifactBindingState {
  bindingId: string;
  fileVersionId: string;
  boundVersionNumber: number;
  strength: ArtifactBindingStrength;
  version: number;
}

export interface UpstreamArtifact {
  upstreamTaskId: string;
  upstreamTaskTitle: string;
  fileId: string;
  logicalName: string;
  versions: FormalArtifactVersion[];
  latestVersionId: string;
  binding: ArtifactBindingState | null;
}

export interface UpstreamArtifactsSnapshot {
  downstreamTaskId: string;
  canBind: boolean;
  artifacts: UpstreamArtifact[];
}

export function findArtifactVersion(
  artifact: UpstreamArtifact,
  fileVersionId: string | undefined,
) {
  if (!fileVersionId) return undefined;
  return artifact.versions.find(
    (version) => version.fileVersionId === fileVersionId,
  );
}

export function latestArtifactVersion(artifact: UpstreamArtifact) {
  return findArtifactVersion(artifact, artifact.latestVersionId);
}

export function artifactHasUpdate(artifact: UpstreamArtifact) {
  const binding = artifact.binding;
  const latest = latestArtifactVersion(artifact);
  if (!binding || !latest) return false;
  return latest.versionNumber > binding.boundVersionNumber;
}
