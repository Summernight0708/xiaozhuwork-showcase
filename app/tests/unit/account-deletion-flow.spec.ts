import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import AccountDeletionFlow from "@/components/account/AccountDeletionFlow.vue";

const mocks = vi.hoisted(() => ({
  status: vi.fn(),
  cancel: vi.fn(),
  request: vi.fn(),
  refreshProfile: vi.fn(),
  replace: vi.fn(),
}));
vi.mock("vue-router", () => ({
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock("@/stores/auth", () => ({
  useAuthStore: () => ({ refreshProfile: mocks.refreshProfile }),
}));
vi.mock("@/features/account-lifecycle/repository", async (original) => ({
  ...(await original<object>()),
  getAccountLifecycleStatus: mocks.status,
  cancelAccountDeletion: mocks.cancel,
  requestAccountDeletion: mocks.request,
}));

describe("gated account cancellation flow", () => {
  let wrapper: VueWrapper;
  const pending = {
    state: "pending",
    version: 1,
    cancelUntil: "2026-10-12T00:00:02Z",
  };
  const button = (text: string) =>
    wrapper.findAll("button").find((item) => item.text() === text)!;

  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-12T00:00:00Z"));
    mocks.status.mockResolvedValue(pending);
    mocks.cancel.mockResolvedValue({ ok: true });
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.useRealTimers();
  });

  it("restores profile and settings after successful self cancellation", async () => {
    wrapper = mount(AccountDeletionFlow);
    await flushPromises();
    await button("撤销注销申请").trigger("click");
    await flushPromises();
    expect(mocks.cancel).toHaveBeenCalledWith(expect.any(String), 1);
    expect(mocks.refreshProfile).toHaveBeenCalledOnce();
    expect(mocks.replace).toHaveBeenCalledWith({ name: "account-settings" });
  });

  it("reuses the exact command key after an uncertain transport failure", async () => {
    mocks.cancel.mockRejectedValueOnce(new Error("网络暂时不可用"));
    wrapper = mount(AccountDeletionFlow);
    await flushPromises();
    await button("撤销注销申请").trigger("click");
    await flushPromises();
    await button("撤销注销申请").trigger("click");
    await flushPromises();
    expect(mocks.cancel.mock.calls[1]).toEqual(mocks.cancel.mock.calls[0]);
  });

  it("uses a new command key after authoritative version refresh", async () => {
    mocks.cancel.mockRejectedValueOnce(
      new Error("账号状态已变化，请刷新后重试"),
    );
    wrapper = mount(AccountDeletionFlow);
    await flushPromises();
    await button("撤销注销申请").trigger("click");
    await flushPromises();
    mocks.status.mockResolvedValue({ ...pending, version: 2 });
    await button("重新读取状态").trigger("click");
    await flushPromises();
    await button("撤销注销申请").trigger("click");
    await flushPromises();
    expect(mocks.cancel.mock.calls[1]?.[0]).not.toBe(
      mocks.cancel.mock.calls[0]?.[0],
    );
    expect(mocks.cancel.mock.calls[1]?.[1]).toBe(2);
  });

  it("removes the cancellation action when the deadline passes while open", async () => {
    wrapper = mount(AccountDeletionFlow);
    await flushPromises();
    expect(button("撤销注销申请")).toBeDefined();
    await vi.advanceTimersByTimeAsync(2_000);
    expect(button("撤销注销申请")).toBeUndefined();
    expect(mocks.cancel).not.toHaveBeenCalled();
  });

  it.each(["blocked", "redacted"])(
    "does not offer recovery for %s",
    async (state) => {
      mocks.status.mockResolvedValue({ ...pending, state });
      wrapper = mount(AccountDeletionFlow);
      await flushPromises();
      expect(button("撤销注销申请")).toBeUndefined();
      expect(button("申请注销账号")).toBeUndefined();
    },
  );
});
