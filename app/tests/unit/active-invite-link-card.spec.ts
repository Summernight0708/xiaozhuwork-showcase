import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import ActiveInviteLinkCard from "@/components/invitation/ActiveInviteLinkCard.vue";

describe("ActiveInviteLinkCard", () => {
  it("shows active-link actions without any invitation history surface", () => {
    const wrapper = mount(ActiveInviteLinkCard, {
      props: {
        url: "https://example.test/invite/token",
        expiresAt: "2026-10-11T00:00:00Z",
      },
    });

    expect(wrapper.text()).toContain("成员邀请");
    expect(wrapper.text()).toContain("复制链接");
    expect(wrapper.text()).toContain("停止邀请");
    expect(wrapper.text()).not.toContain("邀请记录");
    expect(wrapper.find('[aria-label="复制邀请链接"]').exists()).toBe(true);
  });

  it("uses an accessible stop confirmation and explains existing members are unaffected", async () => {
    const wrapper = mount(ActiveInviteLinkCard, {
      props: {
        url: "https://example.test/invite/token",
        expiresAt: "2026-10-11T00:00:00Z",
      },
    });

    await wrapper.find('[aria-label="停止邀请链接"]').trigger("click");
    expect(wrapper.find('[role="alertdialog"]').exists()).toBe(true);
    expect(wrapper.text()).toContain("已经加入的成员不会受影响");

    const stop = wrapper
      .findAll("button")
      .find((button) => button.text() === "停止邀请");
    await stop!.trigger("click");
    expect(wrapper.emitted("stop")).toHaveLength(1);
  });

  it("does not show a fake renew action when the backend has no renew command", () => {
    const wrapper = mount(ActiveInviteLinkCard, {
      props: {
        url: "https://example.test/invite/token",
        expiresAt: "2026-10-11T00:00:00Z",
        renewable: false,
      },
    });
    expect(wrapper.text()).not.toContain("续期");
  });
});
