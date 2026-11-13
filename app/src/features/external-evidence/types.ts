import type { FollowupCommandMeta } from "@/domain/followup-contracts";

export interface ExternalEvidence {
  id: string;
  projectId: string;
  taskId: string;
  httpsUrl: string;
  host: string;
  description: string;
  submittedBy: string | null;
  createdAt: string;
  updatedAt: string;
  revokedAt: string | null;
  revokedBy: string | null;
  version: number;
}

export interface ExternalEvidenceRevision {
  id: string;
  projectId: string;
  taskId: string;
  evidenceId: string;
  version: number;
  httpsUrl: string;
  host: string;
  description: string;
  submittedBy: string | null;
  evidenceCreatedAt: string;
  evidenceUpdatedAt: string;
  action: "updated" | "removed";
  changedBy: string | null;
  changedAt: string;
  requestId: string;
  commandRequestId: string;
  occurrenceKey: string;
}

export interface EvidenceDraft {
  httpsUrl: string;
  description: string;
}
export type CreateEvidenceInput = FollowupCommandMeta &
  EvidenceDraft & {
    projectId: string;
    taskId: string;
  };
export type UpdateEvidenceInput = FollowupCommandMeta &
  EvidenceDraft & {
    projectId: string;
    evidenceId: string;
  };
export type RemoveEvidenceInput = FollowupCommandMeta & {
  projectId: string;
  evidenceId: string;
};

export type EvidenceCommandResult = {
  requestId: string;
  replayed: boolean;
} & (
  | {
      ok: true;
      data: {
        evidenceId: string;
        taskId: string;
        taskVersion: number;
        evidenceVersion: number;
        revokedAt: string | null;
      };
      aggregateType: "task" | "external_evidence";
      aggregateId: string;
      aggregateVersion: number;
    }
  | {
      ok: false;
      code: string;
      field?: string;
      currentVersion?: number;
      details?: unknown;
    }
);

export interface ExternalEvidenceRepository {
  list(
    projectId: string,
    taskId: string,
    page?: EvidencePage,
  ): Promise<ExternalEvidence[]>;
  revisions(
    projectId: string,
    evidenceId: string,
    page?: EvidencePage,
  ): Promise<ExternalEvidenceRevision[]>;
  create(input: CreateEvidenceInput): Promise<EvidenceCommandResult>;
  update(input: UpdateEvidenceInput): Promise<EvidenceCommandResult>;
  remove(input: RemoveEvidenceInput): Promise<EvidenceCommandResult>;
}

export interface EvidencePage {
  offset: number;
  limit?: number;
}
