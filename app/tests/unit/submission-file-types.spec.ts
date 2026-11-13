import { describe, expect, it } from "vitest";

import {
  normalizeRequiredSubmissionFileTypes,
  submissionFileTypeFromMime,
} from "@/domain/submission-file-types";

describe("required submission file type sets", () => {
  it("treats an empty set as unrestricted and returns a fresh empty array", () => {
    expect(normalizeRequiredSubmissionFileTypes(null)).toEqual([]);
    expect(normalizeRequiredSubmissionFileTypes(undefined)).toEqual([]);
    expect(normalizeRequiredSubmissionFileTypes([])).toEqual([]);
  });

  it("normalizes selected types into whitelist order and removes duplicates", () => {
    expect(
      normalizeRequiredSubmissionFileTypes(["xlsx", "pdf", "xlsx", "doc"]),
    ).toEqual(["pdf", "doc", "xlsx"]);
  });

  it("drops values outside the supported submission type whitelist", () => {
    expect(
      normalizeRequiredSubmissionFileTypes([
        "pdf",
        "exe",
        "application/msword",
      ]),
    ).toEqual(["pdf"]);
  });

  it("maps legacy Word MIME to the doc submission type", () => {
    expect(submissionFileTypeFromMime("application/msword")).toBe("doc");
  });
});
