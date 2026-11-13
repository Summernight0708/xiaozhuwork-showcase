import { describe, expect, it } from "vitest";

import {
  canChangeFinalFileDesignation,
  isFinalDesignationEligibleFile,
} from "@/domain/final-file-access";

describe("final file designation access", () => {
  it("locks designation changes after the contribution report becomes formal", () => {
    expect(
      canChangeFinalFileDesignation({
        canMarkFinalFiles: true,
        projectLifecycle: "active",
        taskStatus: "completed",
        contributionReportState: "formal",
      }),
    ).toBe(false);
  });

  it("allows an active leader to change a completed task designation before formalization", () => {
    expect(
      canChangeFinalFileDesignation({
        canMarkFinalFiles: true,
        projectLifecycle: "active",
        taskStatus: "completed",
        contributionReportState: "draft",
      }),
    ).toBe(true);
  });

  it("never treats task reference material as a final-deliverable candidate", () => {
    expect(isFinalDesignationEligibleFile("reference")).toBe(false);
    expect(isFinalDesignationEligibleFile("deliverable")).toBe(true);
  });
});
