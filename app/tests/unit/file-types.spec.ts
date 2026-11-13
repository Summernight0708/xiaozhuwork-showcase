import { describe, expect, it } from "vitest";

import {
  fileWasUploadedBy,
  matchesFileType,
  matchesFileUpdatedWindow,
  matchesFileUploader,
} from "@/domain/file-types";

describe("project file type filters", () => {
  it.each([
    ["pdf", "report.pdf", "application/pdf"],
    [
      "presentation",
      "slides.pptx",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ],
    [
      "word",
      "report.docx",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ],
    [
      "spreadsheet",
      "data.xlsx",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ],
    ["image", "figure.png", "image/png"],
    ["archive", "submission.zip", "application/zip"],
    ["other", "notes.bin", "application/octet-stream"],
  ] as const)(
    "classifies %s files from approved format groups",
    (type, filename, mimeType) => {
      expect(matchesFileType(type, { filename, mimeType })).toBe(true);
    },
  );

  it("filters by uploader and recent update windows", () => {
    const now = Date.parse("2026-09-30T00:00:00Z");
    expect(matchesFileUploader("all", "user-1")).toBe(true);
    expect(matchesFileUploader("user-1", "user-1")).toBe(true);
    expect(matchesFileUploader("user-1", "user-2")).toBe(false);
    expect(matchesFileUpdatedWindow("day", "2026-09-29T12:00:00Z", now)).toBe(
      true,
    );
    expect(matchesFileUpdatedWindow("week", "2026-09-22T23:59:59Z", now)).toBe(
      false,
    );
    expect(matchesFileUpdatedWindow("month", "2026-09-05T00:00:00Z", now)).toBe(
      true,
    );
  });

  it("treats a file as mine when the user uploaded any immutable version", () => {
    expect(
      fileWasUploadedBy("user-1", "user-2", [
        { uploadedBy: "user-3" },
        { uploadedBy: "user-1" },
      ]),
    ).toBe(true);
    expect(
      fileWasUploadedBy("user-1", "user-2", [{ uploadedBy: "user-3" }]),
    ).toBe(false);
    expect(fileWasUploadedBy("user-1", "user-1", [])).toBe(true);
  });
});
