import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), "utf8");
}

describe("Hallmark workbench design contract", () => {
  it("locks one multi-page design system with light and dark tokens", () => {
    const design = source("design.md");
    const tokens = source("tokens.css");
    const main = source("src/assets/main.css");

    expect(design).toContain("modern-minimal");
    expect(design).toContain("Workbench");
    expect(tokens).toContain(':root[data-theme="dark"]');
    expect(tokens).toContain("--color-accent:");
    expect(main).toContain('@import "../../tokens.css"');
  });

  it("uses a full-width workbench and a normal fixed project rail", () => {
    const shell = source("src/layouts/AppShell.vue");
    const main = source("src/assets/main.css");

    expect(shell).toContain("grid-template-columns: 248px minmax(0, 1fr)");
    expect(shell).toContain("width: 100%");
    expect(main).toMatch(/\.xiaozhuwork-page\s*\{[\s\S]*?width:\s*100%/);
  });

  it("keeps task and file workbench records flat instead of wrapping them in cards", () => {
    const tasks = source("src/views/ProjectTasksView.vue");
    const taskRow = source("src/components/task/TaskListRow.vue");
    const files = source("src/views/ProjectFilesView.vue");

    expect(tasks).not.toContain('class="task-list surface"');
    expect(taskRow).toContain("'selection-mode': selectionMode");
    expect(taskRow).toMatch(/\.task-row\s*\{\s*display:\s*block/);
    expect(files).not.toContain('class="surface storage-usage"');
    expect(files).not.toContain('class="upload-strip surface"');
  });
});
