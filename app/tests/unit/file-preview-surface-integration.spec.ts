import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

function source(relativePath: string) {
  return readFileSync(
    fileURLToPath(new URL(relativePath, import.meta.url)),
    "utf8",
  );
}

describe("file preview surface integration", () => {
  it("integrates preview into the Files version history without binding side effects", () => {
    const filesView = source("../../src/views/ProjectFilesView.vue");

    expect(filesView).toContain("FilePreviewPanel");
    expect(filesView).toContain('@preview="openPreview"');
    expect(filesView).toContain(
      ':file-version="previewVersion(previewTarget)"',
    );
    expect(filesView).not.toContain("@preview-success");
  });

  it("keeps ordinary Task Files preview local and free of binding side effects", () => {
    const taskDetail = source(
      "../../src/components/task/TaskDetailContent.vue",
    );

    expect(taskDetail).toContain('@preview="openTaskVersion"');
    expect(taskDetail).toContain(
      ':file-version="previewVersion(previewedVersion)"',
    );
    expect(taskDetail).not.toContain("@preview-success");
  });
});
