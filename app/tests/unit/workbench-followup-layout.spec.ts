import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { displayStatusLabel } from "@/domain/presentation-labels";

const view = (file: string) => readFileSync(resolve(file), "utf8");

describe("follow-up workbench UI regression", () => {
  it("localizes task detail status in the title and overview", () => {
    const content = view("src/components/task/TaskDetailContent.vue");
    expect(
      content.match(
        /:status="displayStatusLabel\(workspace\.taskDisplayStatus\(task\)\)"/g,
      ),
    ).toHaveLength(2);
    expect(displayStatusLabel("blocked")).toBe("阻塞");
    expect(displayStatusLabel("awaiting_review")).toBe("待验收");
    expect(displayStatusLabel("some_new_enum")).toBe("状态待确认");
  });

  it("uses separated task sections instead of rounded surfaces", () => {
    const section = view("src/components/task-detail/TaskDetailSection.vue");
    const overview = view("src/components/task-detail/TaskOverviewSection.vue");
    const header = view("src/components/task-detail/TaskDetailHeader.vue");
    expect(section).not.toContain('class="task-detail-section surface"');
    expect(section).toContain("border-top: 1px solid var(--tu-border)");
    expect(overview).not.toContain("border-radius: 9px;");
    expect(header).not.toContain("border-radius: var(--tu-radius)");
  });

  it("keeps difficulty inputs visually hidden without viewport-width overflow", () => {
    const form = view("src/components/task/TaskForm.vue");
    expect(form).toContain("clip-path: inset(50%)");
    expect(form).toContain("width: 1px");
    expect(form).toContain("height: 1px");
    expect(form).toContain("input:focus-visible + span");
  });

  it("removes redundant cross-project card layers but preserves search/actions", () => {
    const overview = view("src/views/CrossProjectOverviewView.vue");
    const list = view("src/components/cross-project/CrossProjectList.vue");
    const metrics = view(
      "src/components/cross-project/CrossProjectStatistics.vue",
    );
    expect(overview).not.toContain("border-radius: 18px");
    expect(overview).toContain('class="search-row"');
    expect(list).not.toContain("border-radius: 14px");
    expect(metrics).not.toContain("border-radius: 12px");
  });
});
