import { describe, expect, it } from "vitest";

import {
  approvedFileType,
  isPreviewSupported,
  matchesApprovedProjectFile,
  sortImmutableVersions,
} from "@/domain/project-files-ui";
import {
  selectTaskCurrentAction,
  taskDetailAlerts,
} from "@/domain/task-current-action";

describe("approved project file presentation contract", () => {
  it.each([
    ["pdf", "report.pdf", "application/pdf"],
    [
      "docx",
      "report.docx",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ],
    [
      "xlsx",
      "data.xlsx",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ],
    [
      "pptx",
      "deck.pptx",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ],
    ["image", "plot.png", "image/png"],
    ["text", "notes.md", "text/markdown"],
    ["other", "archive.zip", "application/zip"],
  ] as const)(
    "maps %s to the approved filter taxonomy",
    (expected, name, mime) => {
      expect(approvedFileType(name, mime)).toBe(expected);
    },
  );

  it("keeps final artifact as a range filter instead of a MIME type", () => {
    const file = {
      id: "file-1",
      taskId: "task-1",
      taskTitle: "分析",
      logicalName: "data",
      purpose: "deliverable" as const,
      currentVersionId: "v2",
      uploaderName: "张三",
      updatedAt: "2026-10-01T00:00:00Z",
      finalVersionIds: ["v1"],
      versions: [
        {
          id: "v1",
          fileId: "file-1",
          versionNumber: 1,
          originalName: "data.xlsx",
          mimeType:
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          sizeBytes: 10,
          createdAt: "2026-09-30T00:00:00Z",
        },
        {
          id: "v2",
          fileId: "file-1",
          versionNumber: 2,
          originalName: "data.xlsx",
          mimeType:
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          sizeBytes: 12,
          createdAt: "2026-10-01T00:00:00Z",
        },
      ],
    };
    expect(
      matchesApprovedProjectFile(file, {
        search: "",
        type: "xlsx",
        range: "final",
      }),
    ).toBe(true);
    expect(
      matchesApprovedProjectFile(
        { ...file, finalVersionIds: [] },
        { search: "", type: "xlsx", range: "final" },
      ),
    ).toBe(false);
  });

  it("sorts immutable history newest first and knows supported preview formats", () => {
    expect(
      sortImmutableVersions([{ versionNumber: 1 }, { versionNumber: 3 }]).map(
        (item) => item.versionNumber,
      ),
    ).toEqual([3, 1]);
    expect(isPreviewSupported("report.pdf", "application/pdf")).toBe(true);
    expect(isPreviewSupported("archive.7z", "application/octet-stream")).toBe(
      false,
    );
  });
});

describe("task current action selector", () => {
  const base = {
    pendingChangeConfirmation: false,
    pendingCollaborationInvite: false,
    canReview: false,
    isPrimary: false,
    needsChanges: false,
    canFinalSubmit: false,
    isAcceptedCollaborator: false,
    canUpload: false,
  };

  it("prioritizes change confirmation over other actions", () => {
    expect(
      selectTaskCurrentAction({
        ...base,
        pendingChangeConfirmation: true,
        canReview: true,
        isPrimary: true,
        canFinalSubmit: true,
      }),
    ).toEqual({ kind: "confirm-change", label: "查看并确认" });
  });

  it("selects the approved primary, collaborator and reviewer actions", () => {
    expect(
      selectTaskCurrentAction({
        ...base,
        isPrimary: true,
        canFinalSubmit: true,
      })?.kind,
    ).toBe("submit-review");
    expect(
      selectTaskCurrentAction({
        ...base,
        isPrimary: true,
        needsChanges: true,
        canFinalSubmit: true,
      })?.kind,
    ).toBe("resubmit");
    expect(selectTaskCurrentAction({ ...base, canReview: true })?.kind).toBe(
      "open-review",
    );
    expect(
      selectTaskCurrentAction({
        ...base,
        isAcceptedCollaborator: true,
        canUpload: true,
      })?.kind,
    ).toBe("upload-file");
  });

  it("promotes action-relevant alerts without duplicating full section details", () => {
    expect(
      taskDetailAlerts({
        needsChanges: true,
        rejectionReason: "补充数据来源",
        waitingUpstream: true,
        activeIssueCount: 1,
      }).map((item) => item.id),
    ).toEqual(["needs-changes", "waiting-upstream", "active-issues"]);
  });
});
