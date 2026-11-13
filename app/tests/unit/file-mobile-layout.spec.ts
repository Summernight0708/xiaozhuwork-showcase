import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

function source(relativePath: string) {
  return readFileSync(
    fileURLToPath(new URL(relativePath, import.meta.url)),
    "utf8",
  );
}

describe("mobile file surfaces", () => {
  it("keeps the file list bounded with very long names", () => {
    const fileList = source("../../src/components/files/ProjectFileList.vue");

    expect(fileList).toMatch(/\.file-table\s*\{[^}]*table-layout:\s*fixed;/s);
    expect(fileList).toMatch(
      /\.file-anchor strong,[\s\S]*overflow-wrap:\s*anywhere;/s,
    );
    expect(fileList).toMatch(/\.file-anchor\s*\{[^}]*min-width:\s*0;/s);
  });

  it("uses a full-width mobile file drawer with wrapping actions and history", () => {
    const drawer = source("../../src/components/files/FileDetailDrawer.vue");
    const history = source("../../src/components/files/FileVersionHistory.vue");

    expect(drawer).toContain('class="file-detail-popup"');
    expect(drawer).toMatch(
      /@media \(max-width: 560px\)[\s\S]*\.file-detail-popup\s*\{[^}]*width:\s*100vw;/s,
    );
    expect(drawer).toMatch(/\.file-drawer\s*\{[^}]*overflow-y:\s*auto;/s);
    expect(drawer).toMatch(
      /\.drawer-header h2\s*\{[^}]*overflow-wrap:\s*anywhere;/s,
    );
    expect(history).toMatch(/\.version-copy\s*\{[^}]*min-width:\s*0;/s);
    expect(history).toMatch(
      /\.version-copy > span,[\s\S]*overflow-wrap:\s*anywhere;/s,
    );
  });

  it("stacks file filters and upload recovery controls on narrow screens", () => {
    const filesView = source("../../src/views/ProjectFilesView.vue");

    expect(filesView).toMatch(
      /@media \(max-width: 52rem\)[\s\S]*grid-template-columns:\s*minmax\(0, 1fr\);/s,
    );
    expect(filesView).toMatch(
      /\.upload-retry\s*\{[\s\S]*flex-direction:\s*column;/s,
    );
    expect(filesView).toMatch(/\.file-toolbar select,[\s\S]*width:\s*100%;/s);
  });
});
