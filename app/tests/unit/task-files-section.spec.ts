import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import TaskFilesSection from "@/components/task-detail/TaskFilesSection.vue";
import type { TaskFile } from "@/types/ui";

function taskFile(
  id: string,
  name: string,
  purpose: "deliverable" | "reference",
): TaskFile {
  return {
    fileId: id,
    logicalName: name,
    purpose,
    currentVersionId: `${id}-v1`,
    version: 1,
    createdAt: "2026-10-16T00:00:00.000Z",
    updatedAt: "2026-10-16T00:00:00.000Z",
    versions: [
      {
        fileVersionId: `${id}-v1`,
        versionNumber: 1,
        objectPath: `files/${name}`,
        originalName: name,
        mimeType: "application/pdf",
        sizeBytes: 100,
        sha256Hex: "a".repeat(64),
        createdAt: "2026-10-16T00:00:00.000Z",
        purpose,
      },
    ],
  } as TaskFile;
}

describe("TaskFilesSection reference material", () => {
  it("separates task reference material from deliverable files", () => {
    const wrapper = mount(TaskFilesSection, {
      props: {
        files: [
          taskFile("ref", "原始模板.pdf", "reference"),
          taskFile("out", "填写结果.pdf", "deliverable"),
        ],
      },
    });

    expect(wrapper.text()).toContain("任务资料");
    expect(wrapper.text()).toContain("成果文件");
    expect(wrapper.text()).toContain("原始模板.pdf");
    expect(wrapper.text()).toContain("填写结果.pdf");
    expect(wrapper.text()).not.toContain("Task Files");
  });
});
