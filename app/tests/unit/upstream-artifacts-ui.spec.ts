import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import UpstreamArtifactsSection from "@/components/task-detail/UpstreamArtifactsSection.vue";

function group(
  binding: "none" | "light" | "strong" = "none",
  boundVersion = 3,
) {
  return [
    {
      taskId: "upstream-1",
      taskTitle: "数据分析",
      taskStatus: "completed",
      artifacts: [
        {
          fileId: "file-1",
          name: "data.xlsx",
          mimeType:
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          versionId: "version-4",
          versionNumber: 4,
          latestVersionId: "version-4",
          latestVersionNumber: 4,
          binding:
            binding === "none"
              ? { kind: "none" as const }
              : {
                  kind: binding,
                  versionId: "version-" + boundVersion,
                  versionNumber: boundVersion,
                },
        },
      ],
    },
  ];
}

describe("upstream artifact binding surface", () => {
  it("does not create a light binding from preview click alone", async () => {
    const wrapper = mount(UpstreamArtifactsSection, {
      props: { groups: group(), canBind: true },
    });

    await wrapper
      .get('button[aria-label="预览上游成果 data.xlsx"]')
      .trigger("click");

    expect(wrapper.emitted("preview")).toHaveLength(1);
    expect(wrapper.emitted("lightBind")).toBeUndefined();
  });

  it("allows light binding only after trusted success for the exact previewed version", async () => {
    const wrapper = mount(UpstreamArtifactsSection, {
      props: {
        groups: group(),
        canBind: true,
        trustedPreviewSuccessVersionId: null,
      },
    });

    await wrapper
      .get('button[aria-label="预览上游成果 data.xlsx"]')
      .trigger("click");
    await wrapper.setProps({ trustedPreviewSuccessVersionId: "other-version" });
    expect(wrapper.emitted("lightBind")).toBeUndefined();

    await wrapper.setProps({ trustedPreviewSuccessVersionId: "version-4" });
    expect(wrapper.emitted("lightBind")).toHaveLength(1);
  });

  it("requires explicit strong bind and explicit version switch", async () => {
    const wrapper = mount(UpstreamArtifactsSection, {
      props: { groups: group("strong", 3), canBind: true },
    });

    expect(wrapper.text()).toContain("当前强绑定 v3");
    expect(wrapper.text()).toContain("切换到 v4");
    expect(wrapper.emitted("switchVersion")).toBeUndefined();

    const switchButton = wrapper
      .findAll("button")
      .find((button) => button.text().includes("切换到 v4"));
    await switchButton?.trigger("click");

    expect(wrapper.emitted("switchVersion")).toHaveLength(1);
  });
});
