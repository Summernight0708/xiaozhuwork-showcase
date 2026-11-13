import { mount } from "@vue/test-utils";
import { describe, expect, test } from "vitest";
import ExternalEvidenceForm from "@/components/evidence/ExternalEvidenceForm.vue";
import ExternalEvidenceList from "@/components/evidence/ExternalEvidenceList.vue";
import type { ExternalEvidence } from "@/features/external-evidence/types";

const evidence: ExternalEvidence = {
  id: "e",
  projectId: "p",
  taskId: "t",
  httpsUrl: "https://github.com/team/repo",
  host: "github.com",
  description: "<script>alert('x')</script>",
  submittedBy: null,
  createdAt: "2026-10-10T00:00:00Z",
  updatedAt: "2026-10-10T00:00:00Z",
  revokedAt: null,
  revokedBy: null,
  version: 1,
};
describe("external evidence components", () => {
  test("validates the form and emits metadata without fetching a URL", async () => {
    const wrapper = mount(ExternalEvidenceForm);
    await wrapper.get("input").setValue("https://127.0.0.1");
    await wrapper.get("textarea").setValue("Source evidence");
    await wrapper.get("form").trigger("submit");
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.emitted("submit")).toBeUndefined();
    await wrapper.get("input").setValue(evidence.httpsUrl);
    await wrapper.get("form").trigger("submit");
    expect(wrapper.emitted("submit")?.[0]).toEqual([
      { httpsUrl: evidence.httpsUrl, description: "Source evidence" },
    ]);
    await wrapper.get("textarea").setValue("");
    await wrapper.get("form").trigger("submit");
    expect(wrapper.emitted("submit")?.[1]).toEqual([
      { httpsUrl: evidence.httpsUrl, description: "" },
    ]);
    await wrapper.setProps({ disabled: true });
    await wrapper.get("form").trigger("submit");
    expect(wrapper.emitted("submit")).toHaveLength(2);
  });
  test("escapes text, isolates external windows, hides revoked links and read-only actions", async () => {
    const wrapper = mount(ExternalEvidenceList, {
      props: { items: [evidence] },
    });
    expect(wrapper.find("script").exists()).toBe(false);
    expect(wrapper.get("a").attributes("rel")).toBe("noopener noreferrer");
    expect(wrapper.get("a").attributes("referrerpolicy")).toBe("no-referrer");
    expect(wrapper.text()).toContain("已注销成员");
    expect(wrapper.findAll("button")).toHaveLength(1);
    await wrapper.setProps({ editableIds: ["e"] });
    expect(wrapper.findAll("button")).toHaveLength(3);
    await wrapper.setProps({
      items: [{ ...evidence, revokedAt: "2026-10-11T00:00:00Z" }],
    });
    expect(wrapper.find("a").exists()).toBe(false);
    expect(wrapper.findAll("button")).toHaveLength(0);
    expect(wrapper.text()).toContain("暂无外部链接证据");
    await wrapper.setProps({
      items: [{ ...evidence, httpsUrl: "javascript:alert(1)" }],
    });
    expect(wrapper.find("a").exists()).toBe(false);
  });
});
