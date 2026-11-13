import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import TaskDetailHeader from "@/components/task-detail/TaskDetailHeader.vue";
import TaskDetailSection from "@/components/task-detail/TaskDetailSection.vue";
import TaskFilesSection from "@/components/task-detail/TaskFilesSection.vue";
import TaskSubmissionSection from "@/components/task-detail/TaskSubmissionSection.vue";

describe("approved task detail presentation", () => {
  it("uses accessible accordion state and supports overview default-open", async () => {
    const wrapper = mount(TaskDetailSection, {
      props: { title: "概况", defaultOpen: true },
      slots: { default: "<p>overview</p>" },
    });

    const button = wrapper.get("button");
    expect(button.attributes("aria-expanded")).toBe("true");
    expect(wrapper.text()).toContain("overview");

    await button.trigger("click");
    expect(button.attributes("aria-expanded")).toBe("false");
  });

  it("renders one highlighted current action in the header", async () => {
    const wrapper = mount(TaskDetailHeader, {
      props: {
        title: "数据分析",
        status: "进行中",
        primaryName: "张三",
        collaboratorNames: ["李四", "王五", "赵六"],
        deadlineAt: "2026-10-06T10:00:00Z",
        weight: 3,
        currentAction: { kind: "submit-review", label: "提交验收" },
      },
    });

    expect(wrapper.text()).toContain("主负责人");
    expect(wrapper.text()).toContain("李四、王五 +1");
    expect(wrapper.findAll(".current-action")).toHaveLength(1);

    await wrapper.get(".current-action").trigger("click");
    expect(wrapper.emitted("action")).toHaveLength(1);
  });

  it("keeps unified submission as text plus zero-to-many selected file versions", async () => {
    const versions = [
      {
        fileVersionId: "v1",
        versionNumber: 1,
        objectPath: "a",
        originalName: "data.xlsx",
        mimeType: "application/octet-stream",
        sizeBytes: 10,
        sha256Hex: "a".repeat(64),
        createdAt: "2026-10-01T00:00:00Z",
      },
      {
        fileVersionId: "v2",
        versionNumber: 2,
        objectPath: "b",
        originalName: "report.pdf",
        mimeType: "application/pdf",
        sizeBytes: 11,
        sha256Hex: "b".repeat(64),
        createdAt: "2026-10-02T00:00:00Z",
      },
    ];

    const wrapper = mount(TaskSubmissionSection, {
      props: { isPrimary: true, availableVersions: versions },
    });

    const boxes = wrapper.findAll('input[type="checkbox"]');
    await boxes[0]!.setValue(true);
    await boxes[1]!.setValue(true);
    await wrapper.get("textarea").setValue("本轮说明");
    await wrapper.get(".submit-button").trigger("click");

    expect(wrapper.emitted("submit")?.[0]?.[0]).toEqual({
      text: "本轮说明",
      fileVersionIds: ["v1", "v2"],
    });
    expect(wrapper.text()).not.toContain("file submission");
    expect(wrapper.text()).not.toContain("text submission");
  });

  it("explains collaborator upload authority without granting final submit", () => {
    const wrapper = mount(TaskSubmissionSection, {
      props: { isPrimary: false, isAcceptedCollaborator: true },
    });

    expect(wrapper.text()).toContain("最终提交由主负责人完成");
    expect(wrapper.find(".submit-button").exists()).toBe(false);
  });

  it("ordinary task file preview exposes no artifact binding event", async () => {
    const files = [
      {
        fileId: "file-1",
        logicalName: "work.pdf",
        currentVersionId: "v1",
        version: 1,
        createdAt: "2026-10-01T00:00:00Z",
        updatedAt: "2026-10-01T00:00:00Z",
        versions: [
          {
            fileVersionId: "v1",
            versionNumber: 1,
            objectPath: "files/work.pdf",
            originalName: "work.pdf",
            mimeType: "application/pdf",
            sizeBytes: 10,
            sha256Hex: "a".repeat(64),
            createdAt: "2026-10-01T00:00:00Z",
          },
        ],
      },
    ];

    const wrapper = mount(TaskFilesSection, { props: { files } });
    await wrapper
      .get('button[aria-label="预览任务文件 work.pdf"]')
      .trigger("click");

    expect(wrapper.emitted("preview")).toHaveLength(1);
    expect(wrapper.emitted("lightBind")).toBeUndefined();
    expect(wrapper.text()).not.toContain("强绑定");
  });
});
