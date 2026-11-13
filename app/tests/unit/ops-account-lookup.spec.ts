import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  callOpsApi: vi.fn(),
  session: {
    access_token: "user-token",
  },
}));

vi.mock("@ops/lib/ops-api", () => ({
  callOpsApi: mocks.callOpsApi,
}));

vi.mock("@ops/stores/auth", () => ({
  useOpsAuthStore: () => ({
    session: mocks.session,
  }),
}));

import AccountSupportLookup from "@ops/components/AccountSupportLookup.vue";
import { isExactAccountLookup } from "@ops/features/account/lookup";

describe("Ops account support lookup", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it.each(["target@example.test", "0b000000-0000-0000-0000-000000000001"])(
    "accepts exact account lookup %s",
    (query) => {
      expect(isExactAccountLookup(query)).toBe(true);
    },
  );

  it.each([
    "target",
    "%@example.test",
    "target%@example.test",
    "target_@example.test",
    "example.test",
    "",
  ])("rejects non-exact or wildcard lookup %s", (query) => {
    expect(isExactAccountLookup(query)).toBe(false);
  });

  it("renders only approved L1 fields even if the API fixture contains content extras", async () => {
    mocks.callOpsApi.mockResolvedValue({
      ok: true,
      data: {
        schemaVersion: 1,
        userId: "0b000000-0000-0000-0000-000000000001",
        email: "target@example.test",
        createdAt: "2026-10-01T00:00:00Z",
        lastSignInAt: "2026-10-14T08:00:00Z",
        accountState: "active",
        activeProjectCount: 2,
        historicalProjectCount: 4,
        plan: "pro",
        entitlementState: "active",
        proExpiresAt: "2026-11-14T00:00:00Z",
        recentActivity: [
          { eventType: "task_submitted", at: "2026-10-14T07:00:00Z" },
        ],
        taskTitle: "SECRET TASK",
        projectName: "SECRET PROJECT",
        fileName: "SECRET FILE.pdf",
        body: "SECRET BODY",
      },
    });
    const wrapper = mount(AccountSupportLookup);

    await wrapper
      .get('input[name="account-query"]')
      .setValue("target@example.test");
    await wrapper.get("form").trigger("submit");
    await flushPromises();

    expect(mocks.callOpsApi).toHaveBeenCalledOnce();
    const input = mocks.callOpsApi.mock.calls[0]?.[0] as Record<
      string,
      unknown
    >;
    expect(input.action).toBe("account.lookup");
    expect(input.query).toBe("target@example.test");
    expect(input).not.toHaveProperty("dimension");
    expect(input).not.toHaveProperty("filter");

    const text = wrapper.text();
    expect(text).toContain("target@example.test");
    expect(text).toContain("task_submitted");
    expect(text).not.toContain("SECRET TASK");
    expect(text).not.toContain("SECRET PROJECT");
    expect(text).not.toContain("SECRET FILE");
    expect(text).not.toContain("SECRET BODY");
  });

  it("contains no arbitrary dimension/filter controls", () => {
    const wrapper = mount(AccountSupportLookup);
    expect(wrapper.find('[name="dimension"]').exists()).toBe(false);
    expect(wrapper.find('[name="filter"]').exists()).toBe(false);
    expect(wrapper.findAll("input")).toHaveLength(1);
  });
});
