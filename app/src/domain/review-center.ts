import {
  isSubmissionFileType,
  submissionFileTypeFromMime,
} from "@/domain/submission-file-types";
import type {
  ReviewRoundFileRow,
  ReviewRoundRow,
  TaskFile,
  TaskRow,
} from "@/types/ui";
import type {
  ReviewAttachmentSnapshot,
  ReviewRoundSnapshot,
} from "@/types/frontend-integration";

export type ReviewQueueFilter = "pending" | "processed";

function reviewAttachments(
  round: ReviewRoundRow,
  roundFiles: readonly ReviewRoundFileRow[],
  taskFiles: readonly TaskFile[],
): ReviewAttachmentSnapshot[] {
  const ordered = roundFiles
    .filter((item) => item.review_round_id === round.id)
    .sort((left, right) => left.position - right.position);

  return ordered.flatMap((item) => {
    for (const file of taskFiles) {
      const version = file.versions.find(
        (candidate) => candidate.fileVersionId === item.file_version_id,
      );
      if (!version) continue;
      return [
        {
          fileId: file.fileId,
          fileVersionId: version.fileVersionId,
          versionNumber: version.versionNumber,
          originalName: version.originalName,
          mimeType: version.mimeType,
          sizeBytes: version.sizeBytes,
          objectPath: version.objectPath,
        },
      ];
    }
    return [];
  });
}

export function buildReviewSnapshot(input: {
  round: ReviewRoundRow;
  roundFiles: readonly ReviewRoundFileRow[];
  task: TaskRow;
  taskFiles: readonly TaskFile[];
  memberName: (userId?: string | null) => string;
}): ReviewRoundSnapshot {
  const { round, task } = input;
  const attachments = reviewAttachments(
    round,
    input.roundFiles,
    input.taskFiles,
  );
  const snapshotTypes = round.required_submission_file_types_snapshot ?? [];
  const requiredTypes = snapshotTypes.length
    ? snapshotTypes.filter(isSubmissionFileType)
    : isSubmissionFileType(round.required_submission_file_type_snapshot)
      ? [round.required_submission_file_type_snapshot]
      : [];

  return {
    id: round.id,
    taskId: round.task_id,
    taskTitle: task.title,
    roundNumber: round.round_number,
    submitterId: round.submitted_by,
    submitterName: input.memberName(round.submitted_by),
    submittedAt: round.submitted_at,
    state: round.state,
    decision: round.decision,
    reviewComment: round.rejection_reason,
    reviewedAt: round.reviewed_at,
    correctionOfReviewRoundId: round.correction_of_review_round_id,
    textSnapshot: round.submission_text_snapshot,
    attachments,
    requirement: requiredTypes.length
      ? {
          requiredFileTypes: requiredTypes,
          satisfied: attachments.some((attachment) => {
            const type = submissionFileTypeFromMime(attachment.mimeType);
            return type !== null && requiredTypes.includes(type);
          }),
        }
      : null,
  };
}

export function matchesReviewQueue(
  snapshot: ReviewRoundSnapshot,
  filter: ReviewQueueFilter,
) {
  return filter === "pending"
    ? snapshot.state === "pending"
    : snapshot.state !== "pending";
}

export function reviewHistoryForTask(
  snapshots: readonly ReviewRoundSnapshot[],
  taskId: string,
) {
  return snapshots
    .filter((round) => round.taskId === taskId)
    .sort((a, b) => b.roundNumber - a.roundNumber);
}
