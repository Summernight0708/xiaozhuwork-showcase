import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import CalendarSubscriptionCreate from "@/components/integrations/CalendarSubscriptionCreate.vue";
import CalendarSubscriptionList from "@/components/integrations/CalendarSubscriptionList.vue";
import CalendarSubscriptionSecurityNotice from "@/components/integrations/CalendarSubscriptionSecurityNotice.vue";

describe("E calendar subscription interface", () => {
  it("starts with redacted titles and requires explicit opt-in", async () => {
    const wrapper = mount(CalendarSubscriptionCreate, {
      props: { disabled: false, pending: false },
    });
    expect(
      (wrapper.get('input[type="checkbox"]').element as HTMLInputElement)
        .checked,
    ).toBe(false);
    await wrapper.get('button[type="button"]').trigger("click");
    expect(wrapper.emitted("create")?.[0]).toEqual([false]);
    await wrapper.get('input[type="checkbox"]').setValue(true);
    expect(wrapper.text()).toContain("缓存");
    await wrapper.get('button[type="button"]').trigger("click");
    expect(wrapper.emitted("create")?.[1]).toEqual([true]);
  });
  it("disables issuance without permission or capability", () => {
    const wrapper = mount(CalendarSubscriptionCreate, {
      props: { disabled: true, pending: false },
    });
    expect(wrapper.get("button").attributes("disabled")).toBeDefined();
    expect(
      wrapper.get('input[type="checkbox"]').attributes("disabled"),
    ).toBeDefined();
  });
  it("lists metadata without credentials and supports revocation", async () => {
    const wrapper = mount(CalendarSubscriptionList, {
      props: {
        items: [
          {
            id: "subscription-1",
            createdAt: "2026-10-06T00:00:00Z",
            expiresAt: "2026-12-31T00:00:00Z",
            revokedAt: null,
            showTitles: false,
            version: 1,
          },
        ],
        pendingId: null,
        canRevoke: true,
      },
    });
    expect(wrapper.text()).toContain("隐藏");
    expect(wrapper.text()).not.toContain("token_hash");
    await wrapper.get("button").trigger("click");
    expect((wrapper.emitted("revoke")?.[0] as unknown[])?.[0]).toMatchObject({
      id: "subscription-1",
      version: 1,
    });
  });
  it("warns that third-party caches cannot be erased", () => {
    const wrapper = mount(CalendarSubscriptionSecurityNotice);
    expect(wrapper.text()).toContain("第三方");
    expect(wrapper.text()).toContain("不能清除");
    expect(wrapper.text()).toContain("90 天");
  });
});
