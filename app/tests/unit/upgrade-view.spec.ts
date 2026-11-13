import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getMyAccountEntitlement: vi.fn(),
}));

vi.mock("@/services/backend", () => ({
  getBackend: () => ({ client: {} }),
}));

vi.mock("@/services/repository", () => ({
  createRepository: () => ({
    getMyAccountEntitlement: mocks.getMyAccountEntitlement,
  }),
}));

import UpgradeView from "@/views/UpgradeView.vue";

const pageStateStub = {
  props: ["loading", "error"],
  emits: ["retry"],
  template: `
    <div>
      <div v-if="loading">正在加载…</div>
      <div v-else-if="error" role="alert">
        <span>{{ error }}</span>
        <button type="button" @click="$emit('retry')">重试</button>
      </div>
      <slot v-else />
    </div>
  `,
};

async function mountView() {
  const wrapper = mount(UpgradeView, {
    global: {
      stubs: {
        PageState: pageStateStub,
      },
    },
  });
  await flushPromises();
  return wrapper;
}

describe("UpgradeView", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getMyAccountEntitlement.mockResolvedValue({
      plan: "free",
      state: "free",
      startsAt: null,
      expiresAt: null,
      version: 0,
    });
  });

  it("shows shipped capabilities, planned unreleased Phase 2 benefits, and project Pro rules", async () => {
    const wrapper = await mountView();
    const text = wrapper.text();

    expect(text).toContain("当前账号方案");
    expect(text).toContain("Free");
    expect(text).toContain("活跃 Free 项目");
    expect(text).toContain("最多 5 个");
    expect(text).toContain("不限");
    expect(text).toContain("项目成员");
    expect(text).toContain("Free 项目最多 8 人");
    expect(text).toContain("Pro 项目最多 20 人");
    expect(text).toContain("并发任务");
    expect(text).toContain("Free 项目最多 20 个");
    expect(text).toContain("Pro 项目最多 100 个");
    expect(text).toContain("单文件大小");
    expect(text).toContain("最大 50 MiB / 文件");
    expect(text).toContain("最大 200 MiB / 文件");
    expect(text).toContain("项目文件存储空间");
    expect(text).toContain("约 0.5 GiB / 项目");
    expect(text).toContain("约 5 GiB / 项目");
    expect(text).toContain("完整文件历史");
    expect(text).toContain("最近 10 个版本");
    expect(text).toContain("完整版本历史");
    expect(text).toContain("批量回滚");
    expect(text).toContain("支持批量回滚");
    expect(text).toContain("版本比较");
    expect(text).toContain("文件版本比较");
    expect(text).toContain("项目文件恢复点");
    expect(text).toContain("支持项目文件恢复点");
    expect(text).toContain("增强报告");
    expect(text).toContain("高级权限");
    expect(text).toContain("项目统计");
    expect(text).toContain("跨项目总览与搜索");
    expect(text).toContain("跨项目汇总与统计");
    expect(text).toContain("外部集成");
    expect(text).toContain("以下权益均已正式上线。");
    expect(text).not.toContain("待集成");
    expect(text).not.toContain("规划中");
    expect(wrapper.find(".release-status").exists()).toBe(false);
    expect(text).toContain("组长、管理员或成员");
    expect(text).toContain("观察者身份不触发项目 Pro");
    expect(text).toContain("人工确认方案");
    expect(text).toContain("人工开通");
    expect(text).toContain("your_wechat_id");
    expect(text).not.toContain("月付");
    expect(text).not.toContain("年付");
    expect(text).not.toMatch(/¥\s*\d/);
    expect(text).not.toMatch(/￥\s*\d/);
    expect(text).not.toContain("立即购买");
    expect(text).not.toContain("套餐");
    expect(text).not.toContain("TeamUp");
    expect(text).not.toContain("PDF visual diff");
    expect(text).not.toContain("Office visual diff");
    expect(text).not.toContain("全文件内容比较");
    expect(text).not.toContain("完整数据库恢复");
    expect(text).not.toContain("整个项目时光机");
    expect(text).not.toContain("任务状态恢复");
  });

  it("orders account, contact, full comparison, then the value themes", async () => {
    const wrapper = await mountView();
    const account = wrapper.find(".account-plan-summary").element;
    const contact = wrapper.find(".manual-upgrade").element;
    const themes = wrapper.find(".pro-value-themes").element;
    const comparison = wrapper.find(".benefits-section").element;

    expect(
      account.compareDocumentPosition(contact) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      contact.compareDocumentPosition(comparison) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      comparison.compareDocumentPosition(themes) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();

    expect(wrapper.text()).toContain("更大空间");
    expect(wrapper.text()).toContain("更安心的成果管理");
    expect(wrapper.text()).toContain("更强的项目管理");
    expect(wrapper.text()).toContain("your_wechat_id");
    expect(wrapper.text()).not.toContain("立即购买");
    expect(wrapper.text()).not.toMatch(/¥\s*\d/);
  });

  it("shows active Pro and its account expiry", async () => {
    mocks.getMyAccountEntitlement.mockResolvedValue({
      plan: "pro",
      state: "active",
      startsAt: "2026-10-01T00:00:00.000Z",
      expiresAt: "2027-01-15T12:00:00.000Z",
      version: 2,
    });

    const wrapper = await mountView();

    expect(wrapper.text()).toContain("Pro");
    expect(wrapper.text()).not.toContain("Early Access Pro");
    expect(wrapper.text()).toContain("有效期至");
    expect(wrapper.text()).toContain("2027");
  });

  it.each([
    ["scheduled", "Pro 已安排", "将于"],
    ["expired", "Pro 已到期", "当前有效方案为 Free"],
    ["cancelled", "Pro 已取消", "当前有效方案为 Free"],
  ] as const)(
    "presents %s without treating the account as active Pro",
    async (state, label, detail) => {
      mocks.getMyAccountEntitlement.mockResolvedValue({
        plan: "free",
        state,
        startsAt: "2026-12-01T00:00:00.000Z",
        expiresAt: "2027-01-01T00:00:00.000Z",
        version: 3,
      });

      const wrapper = await mountView();

      expect(wrapper.text()).toContain(label);
      expect(wrapper.text()).toContain(detail);
      expect(wrapper.text()).not.toContain("Early Access Pro");
    },
  );

  it("fails closed when account entitlement loading fails and supports retry", async () => {
    mocks.getMyAccountEntitlement.mockRejectedValueOnce(new Error("network"));
    const wrapper = await mountView();

    expect(wrapper.text()).toContain("加载失败，请重试。");
    expect(wrapper.find(".account-plan-summary").exists()).toBe(false);

    mocks.getMyAccountEntitlement.mockResolvedValueOnce({
      plan: "free",
      state: "free",
      startsAt: null,
      expiresAt: null,
      version: 0,
    });
    await wrapper.get("button").trigger("click");
    await flushPromises();

    expect(wrapper.find(".account-plan-summary").exists()).toBe(true);
    expect(wrapper.text()).toContain("当前有效方案为 Free");
  });
});
