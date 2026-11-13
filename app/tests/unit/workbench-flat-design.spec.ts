import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const source = (path: string) => readFileSync(resolve(path), "utf8");

describe("low-card workbench contract", () => {
  it("uses text-first states instead of a giant dashed placeholder", () => {
    const state = source("src/components/common/PageState.vue");
    expect(state).not.toContain("<van-empty");
    expect(state).not.toContain("border: 1px dashed");
    expect(state).toContain('role="alert"');
    expect(state).toContain('name="empty-action"');
  });

  it("makes the project index continuous rather than separate floating cards", () => {
    const view = source("src/views/ProjectsView.vue");
    expect(view).toContain("border-bottom: 1px solid var(--tu-border)");
    expect(view).not.toContain("translateY(-2px)");
    expect(view).not.toContain("border-radius: 16px");
  });

  it("offers progressive file filters while keeping upload and search visible", () => {
    const files = source("src/views/ProjectFilesView.vue");
    expect(files).toContain('class="file-filter-toggle"');
    expect(files).toContain('aria-controls="file-extra-filters"');
    expect(files).toContain("file-toolbar.filters-open .file-extra-filters");
    expect(files).toContain('class="upload-strip"');
  });
});
