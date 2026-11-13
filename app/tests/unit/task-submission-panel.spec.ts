import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const showToast = vi.hoisted(() => vi.fn());

vi.mock("vant", async () => {
  const actual = await vi.importActual<typeof import("vant")>("vant");
  return { ...actual, showToast };
});

import TaskSubmissionPanel from "@/components/task/TaskSubmissionPanel.vue";
import type { TaskFileVersion } from "@/types/ui";

const versions: TaskFileVersion[] = [
  {
    fileVersionId: "pptx-1",
    versionNumber: 1,
    objectPath: "files/slides.pptx",
    originalName: "slides.pptx",
    mimeType:
      "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    sizeBytes: 100,
    sha256Hex: "a".repeat(64),
    createdAt: "2026-10-04T00:00:00Z",
  },
  {
    fileVersionId: "xlsx-1",
    versionNumber: 1,
    objectPath: "files/data.xlsx",
    originalName: "data.xlsx",
    mimeType:
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    sizeBytes: 100,
    sha256Hex: "b".repeat(64),
    createdAt: "2026-10-04T00:00:00Z",
  },
];

function mountPanel(
  overrides: Partial<InstanceType<typeof TaskSubmissionPanel>["$props"]> = {},
) {
  return mount(TaskSubmissionPanel, {
    props: {
      versions,
      requiredFileTypes: [],
      dependencyBlocked: false,
      submitLoading: false,
      uploadLoading: false,
      resetKey: 0,
      autoSelectFileVersionId: null,
      ...overrides,
    },
    global: {
      stubs: {
        "van-button": {
          props: ["disabled", "loading"],
          emits: ["click"],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')"><slot /></button>',
        },
      },
    },
  });
}

function submitButton(wrapper: ReturnType<typeof mountPanel>) {
  return wrapper
    .findAll("button")
    .find((button) => button.text().includes("提交验收"))!;
}

describe("TaskSubmissionPanel", () => {
  beforeEach(() => {
    showToast.mockClear();
  });

  it("allows submission despite unfinished upstream tasks", async () => {
    const wrapper = mountPanel({ dependencyBlocked: true });
    await wrapper.find("textarea").setValue("已完成下游成果");
    expect(submitButton(wrapper).attributes("disabled")).toBeUndefined();
    await submitButton(wrapper).trigger("click");
    expect(wrapper.emitted("submit")?.[0]).toEqual([
      { submissionText: "已完成下游成果", fileVersionIds: [] },
    ]);
  });

  it("labels a no-review submission as finishing the task", async () => {
    const wrapper = mountPanel({ requiresReview: false });
    expect(wrapper.text()).toContain("提交并完成");
  });

  it("submits text only without requiring a file", async () => {
    const wrapper = mountPanel({ versions: [] });
    await wrapper.find("textarea").setValue("  完成了分析  ");
    await submitButton(wrapper).trigger("click");

    expect(wrapper.emitted("submit")?.[0]).toEqual([
      { submissionText: "完成了分析", fileVersionIds: [] },
    ]);
  });

  it("submits a finalized file without text", async () => {
    const wrapper = mountPanel();
    await wrapper.find('input[value="xlsx-1"]').setValue(true);
    await submitButton(wrapper).trigger("click");

    expect(wrapper.emitted("submit")?.[0]).toEqual([
      { fileVersionIds: ["xlsx-1"] },
    ]);
  });

  it("submits text together with multiple selected files", async () => {
    const wrapper = mountPanel();
    await wrapper.find("textarea").setValue("答辩材料完成");
    await wrapper.find('input[value="pptx-1"]').setValue(true);
    await wrapper.find('input[value="xlsx-1"]').setValue(true);
    await submitButton(wrapper).trigger("click");

    expect(wrapper.emitted("submit")?.[0]).toEqual([
      {
        submissionText: "答辩材料完成",
        fileVersionIds: ["pptx-1", "xlsx-1"],
      },
    ]);
  });

  it("keeps an empty submission disabled", () => {
    const wrapper = mountPanel({ versions: [] });
    expect(submitButton(wrapper).attributes("disabled")).toBeDefined();
    expect(wrapper.emitted("submit")).toBeUndefined();
  });

  it("requires the configured trusted file type but permits other attachments too", async () => {
    const wrapper = mountPanel({ requiredFileTypes: ["pptx"] });
    expect(wrapper.text()).toContain("至少包含以下任一类型");
    expect(wrapper.text()).toContain("PPTX");

    await wrapper.find('input[value="xlsx-1"]').setValue(true);
    expect(wrapper.text()).toContain("当前所选附件不包含任何指定类型（PPTX）");
    expect(submitButton(wrapper).attributes("disabled")).toBeDefined();

    await wrapper.find('input[value="pptx-1"]').setValue(true);
    expect(submitButton(wrapper).attributes("disabled")).toBeUndefined();
    await submitButton(wrapper).trigger("click");

    expect(wrapper.emitted("submit")?.[0]).toEqual([
      { fileVersionIds: ["xlsx-1", "pptx-1"] },
    ]);
  });

  it("never offers task reference material as a submission attachment", () => {
    const referenceVersion = {
      ...versions[0]!,
      fileVersionId: "reference-1",
      originalName: "原始表格模板.xlsx",
      purpose: "reference",
    } as TaskFileVersion;
    const wrapper = mountPanel({ versions: [referenceVersion, versions[1]!] });

    expect(wrapper.text()).not.toContain("原始表格模板.xlsx");
    expect(wrapper.find('input[value="reference-1"]').exists()).toBe(false);
    expect(wrapper.find('input[value="xlsx-1"]').exists()).toBe(true);
  });

  it("auto-selects a file version finalized from the submission uploader", async () => {
    const wrapper = mountPanel();
    await wrapper.setProps({ autoSelectFileVersionId: "xlsx-1" });

    expect(
      (wrapper.find('input[value="xlsx-1"]').element as HTMLInputElement)
        .checked,
    ).toBe(true);
    expect(submitButton(wrapper).attributes("disabled")).toBeUndefined();
  });

  it("retains the draft until the parent advances resetKey", async () => {
    const wrapper = mountPanel();
    const textarea = wrapper.find("textarea");
    await textarea.setValue("不要因请求失败清空");
    await wrapper.setProps({ submitLoading: true });
    await wrapper.setProps({ submitLoading: false });
    expect((textarea.element as HTMLTextAreaElement).value).toBe(
      "不要因请求失败清空",
    );

    await wrapper.setProps({ resetKey: 1 });
    expect(
      (wrapper.find("textarea").element as HTMLTextAreaElement).value,
    ).toBe("");
  });

  it("emits uploaded files without turning upload into submission", async () => {
    const wrapper = mountPanel();
    const file = new File(["hello"], "report.pdf", {
      type: "application/pdf",
    });
    const input = wrapper.find('input[type="file"]');
    Object.defineProperty(input.element, "files", {
      configurable: true,
      value: [file],
    });
    await input.trigger("change");

    expect(wrapper.emitted("upload")?.[0]).toEqual([file]);
    expect(wrapper.emitted("submit")).toBeUndefined();
  });
});
