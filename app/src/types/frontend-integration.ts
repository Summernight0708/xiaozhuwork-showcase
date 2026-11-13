export interface ApprovedFileVersion {
  id: string;
  fileId: string;
  versionNumber: number;
  originalName: string;
  mimeType: string;
  sizeBytes: number;
  objectPath?: string;
  uploadedBy?: string | null;
  createdAt: string;
}

export interface ApprovedProjectFile {
  id: string;
  taskId: string;
  taskTitle: string;
  logicalName: string;
  purpose: "deliverable" | "reference";
  currentVersionId?: string | null;
  uploaderName: string;
  updatedAt: string;
  finalVersionIds: readonly string[];
  versions: readonly ApprovedFileVersion[];
}

export interface ReviewAttachmentSnapshot {
  fileId?: string;
  fileVersionId: string;
  versionNumber: number;
  originalName: string;
  mimeType: string;
  sizeBytes: number;
  objectPath?: string;
}

export interface ReviewRequirementSummary {
  requiredFileTypes: readonly string[];
  satisfied: boolean;
}

export interface ReviewRoundSnapshot {
  id: string;
  taskId: string;
  taskTitle: string;
  roundNumber: number;
  submitterId?: string | null;
  submitterName: string;
  submittedAt: string;
  state: string;
  decision?: string | null;
  reviewComment?: string | null;
  reviewedAt?: string | null;
  correctionOfReviewRoundId?: string | null;
  textSnapshot?: string | null;
  attachments: readonly ReviewAttachmentSnapshot[];
  requirement?: ReviewRequirementSummary | null;
}

export type ArtifactBindingKind = "none" | "light" | "strong";

export interface ArtifactBindingPresentation {
  kind: ArtifactBindingKind;
  versionId?: string;
  versionNumber?: number;
}

export interface UpstreamArtifactPresentation {
  fileId: string;
  name: string;
  mimeType: string;
  versionId: string;
  versionNumber: number;
  latestVersionId: string;
  latestVersionNumber: number;
  binding: ArtifactBindingPresentation;
}

export interface UpstreamArtifactGroup {
  taskId: string;
  taskTitle: string;
  taskStatus: string;
  artifacts: readonly UpstreamArtifactPresentation[];
}

export type TaskCurrentActionKind =
  | "confirm-change"
  | "respond-collaboration"
  | "open-review"
  | "resubmit"
  | "submit-review"
  | "upload-file";

export interface TaskCurrentAction {
  kind: TaskCurrentActionKind;
  label: string;
}

export type TaskAlertTone = "warning" | "info" | "danger";

export interface TaskAlertPresentation {
  id: string;
  label: string;
  detail?: string;
  tone: TaskAlertTone;
}
