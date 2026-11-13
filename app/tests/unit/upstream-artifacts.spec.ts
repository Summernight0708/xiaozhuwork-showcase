import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  listUpstreamArtifacts: vi.fn(),
  recordArtifactUse: vi.fn(),
  setBindingStrength: vi.fn(),
  switchBindingVersion: vi.fn(),
}));

vi.mock("@/services/backend", () => ({
  getBackend: () => ({ client: {} }),
}));

vi.mock("@/services/artifact-binding-repository", () => ({
  createArtifactBindingRepository: () => mocks,
}));

vi.mock("@/components/file/FilePreviewPanel.vue", () => ({
  default: {
    props: ["fileVersion"],
    emits: ["close", "preview-success"],
    template:
      '<button class="preview-success-stub" @click="$emit(\'preview-success\', fileVersion.id)">preview success</button>',
  },
}));

import UpstreamArtifacts from "@/components/task/UpstreamArtifacts.vue";

const v3 = {
  fileVersionId: "version-3",
  versionNumber: 3,
  objectPath: "project/upstream/data-v3.xlsx",
  originalName: "data.xlsx",
  mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
};

const v4 = {
  ...v3,
  fileVersionId: "version-4",
  versionNumber: 4,
  objectPath: "project/upstream/data-v4.xlsx",
};

function snapshot(
  strength: "light" | "strong" = "light",
  boundVersionId = "version-3",
) {
  return {
    downstreamTaskId: "task-downstream",
    canBind: true,
    artifacts: [
      {
        upstreamTaskId: "task-upstream",
        upstreamTaskTitle: "数据整理",
        fileId: "file-data",
        logicalName: "data.xlsx",
        versions: [v3, v4],
        latestVersionId: "version-4",
        binding: {
          bindingId: "binding-1",
          fileVersionId: boundVersionId,
          boundVersionNumber: boundVersionId === "version-3" ? 3 : 4,
          strength,
          version: 2,
        },
      },
    ],
  };
}

describe("UpstreamArtifacts", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.listUpstreamArtifacts.mockResolvedValue(snapshot());
    mocks.recordArtifactUse.mockResolvedValue({
      ok: true,
      data: { changed: false },
    });
    mocks.setBindingStrength.mockResolvedValue({
      ok: true,
      data: { changed: true },
    });
    mocks.switchBindingVersion.mockResolvedValue({
      ok: true,
      data: { changed: true },
    });
  });

  it("shows the bound version, latest version, update marker, and accessible strong-binding control", async () => {
    const wrapper = mount(UpstreamArtifacts, {
      props: {
        projectId: "project-1",
        taskId: "task-downstream",
      },
    });
    await flushPromises();

    expect(wrapper.text()).toContain("上游成果");
    expect(wrapper.text()).toContain("数据整理");
    expect(wrapper.text()).toContain("data.xlsx");
    expect(wrapper.text()).toContain("当前使用：v3");
    expect(wrapper.text()).toContain("最新版本：v4");
    expect(wrapper.text()).toContain("上游成果已有更新");
    expect(wrapper.get('[aria-label="强绑定此成果"]').attributes("title")).toBe(
      "强绑定此成果",
    );
  });

  it("records light use only after upstream preview succeeds and never silently switches", async () => {
    const wrapper = mount(UpstreamArtifacts, {
      props: {
        projectId: "project-1",
        taskId: "task-downstream",
      },
    });
    await flushPromises();

    const openButton = wrapper
      .findAll("button")
      .find((button) => button.text().includes("查看 v4"));
    expect(openButton).toBeDefined();
    await openButton!.trigger("click");
    await flushPromises();

    expect(mocks.recordArtifactUse).not.toHaveBeenCalled();
    expect(wrapper.find(".preview-success-stub").exists()).toBe(true);

    await wrapper.get(".preview-success-stub").trigger("click");
    await flushPromises();

    expect(mocks.recordArtifactUse).toHaveBeenCalledWith({
      projectId: "project-1",
      downstreamTaskId: "task-downstream",
      fileVersionId: "version-4",
      requestId: expect.any(String),
    });
    expect(mocks.switchBindingVersion).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain("当前使用：v3");
  });

  it("switches version only after the explicit switch action", async () => {
    mocks.listUpstreamArtifacts
      .mockResolvedValueOnce(snapshot())
      .mockResolvedValueOnce(snapshot("light", "version-4"));

    const wrapper = mount(UpstreamArtifacts, {
      props: {
        projectId: "project-1",
        taskId: "task-downstream",
      },
    });
    await flushPromises();

    const switchButton = wrapper
      .findAll("button")
      .find((button) => button.text().includes("切换到 v4"));
    expect(switchButton).toBeDefined();
    await switchButton!.trigger("click");
    await flushPromises();

    expect(mocks.switchBindingVersion).toHaveBeenCalledWith({
      projectId: "project-1",
      downstreamTaskId: "task-downstream",
      fileVersionId: "version-4",
      requestId: expect.any(String),
      expectedVersion: 2,
    });
    expect(wrapper.text()).toContain("当前使用：v4");
  });

  it("upgrades light to strong without changing the bound file version", async () => {
    mocks.listUpstreamArtifacts
      .mockResolvedValueOnce(snapshot("light"))
      .mockResolvedValueOnce(snapshot("strong"));

    const wrapper = mount(UpstreamArtifacts, {
      props: {
        projectId: "project-1",
        taskId: "task-downstream",
      },
    });
    await flushPromises();

    await wrapper.get('[aria-label="强绑定此成果"]').trigger("click");
    await flushPromises();

    expect(mocks.setBindingStrength).toHaveBeenCalledWith({
      projectId: "project-1",
      downstreamTaskId: "task-downstream",
      fileVersionId: "version-3",
      strength: "strong",
      requestId: expect.any(String),
      expectedVersion: 2,
    });
    expect(wrapper.get('[aria-label="取消强绑定"]').attributes("title")).toBe(
      "取消强绑定",
    );
  });

  it("renders a clear empty state without creating a light binding on load", async () => {
    mocks.listUpstreamArtifacts.mockResolvedValue({
      downstreamTaskId: "task-downstream",
      canBind: true,
      artifacts: [],
    });

    const wrapper = mount(UpstreamArtifacts, {
      props: {
        projectId: "project-1",
        taskId: "task-downstream",
      },
    });
    await flushPromises();

    expect(wrapper.text()).toContain("暂无可使用的上游正式成果");
    expect(mocks.recordArtifactUse).not.toHaveBeenCalled();
  });
});
