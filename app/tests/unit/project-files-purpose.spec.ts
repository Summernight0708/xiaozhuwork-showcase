import { describe, expect, it } from "vitest";

import { buildApprovedProjectFiles } from "@/domain/project-files-ui";
import type { FileRow } from "@/types/ui";

describe("project file purpose presentation", () => {
  it("preserves reference purpose in the approved project file model", () => {
    const file: FileRow = {
      id: "file-1",
      project_id: "project-1",
      task_id: "task-1",
      logical_name: "原始模板.xlsx",
      purpose: "reference",
      created_by: "user-1",
      current_version_id: null,
      version: 1,
      created_at: "2026-10-16T00:00:00.000Z",
      updated_at: "2026-10-16T00:00:00.000Z",
    };

    const [presentation] = buildApprovedProjectFiles({
      files: [file],
      versions: [],
      designations: [],
      tasks: [],
      memberName: () => "成员",
    });

    expect(presentation?.purpose).toBe("reference");
  });
});
