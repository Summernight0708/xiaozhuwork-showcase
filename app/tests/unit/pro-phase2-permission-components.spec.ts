import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import MemberPermissionDelegation from "@/components/permissions/MemberPermissionDelegation.vue";
import PermissionDelegationStatus from "@/components/permissions/PermissionDelegationStatus.vue";
import PermissionTemplateList from "@/components/permissions/PermissionTemplateList.vue";
import type { PermissionSnapshot } from "@/services/project-permissions";

const snapshot: PermissionSnapshot = {
  schemaVersion: 1,
  projectId: "p-1",
  viewerRole: "leader",
  capability: { released: true, entitled: true, effective: true },
  delegations: [],
};
const members = [
  { id: "m-1", displayName: "测试成员", role: "member", version: 3 },
];

describe("D permission components", () => {
  it("shows only two fixed templates", () => {
    const wrapper = mount(PermissionTemplateList);
    expect(wrapper.text()).toContain("邀请管理员");
    expect(wrapper.text()).toContain("入组审核员");
    expect(wrapper.findAll("li")).toHaveLength(2);
  });

  it("emits a version-fenced command for a leader action", async () => {
    const wrapper = mount(MemberPermissionDelegation, {
      props: { members, snapshot, pendingMemberId: null, canEdit: true },
    });
    await wrapper.find("button").trigger("click");
    expect(wrapper.emitted("change")?.[0]).toEqual([
      "m-1",
      "invitation_coordinator",
      true,
      3,
    ]);
  });

  it("never offers active controls before capability release", () => {
    const wrapper = mount(MemberPermissionDelegation, {
      props: { members, snapshot, pendingMemberId: null, canEdit: false },
    });
    expect(
      wrapper
        .findAll("button")
        .every((button) => button.attributes("disabled") !== undefined),
    ).toBe(true);
  });

  it("describes Free suspension without deleting assigned templates", () => {
    const wrapper = mount(PermissionDelegationStatus, {
      props: {
        released: true,
        entitled: false,
        projectState: "free",
        viewerRole: "member",
      },
    });
    expect(wrapper.text()).toContain("记录保留");
    expect(wrapper.text()).toContain("Free");
  });
});
