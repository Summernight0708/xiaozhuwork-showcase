import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  auth: {
    initialized: true,
    error: null as string | null,
    user: {
      id: "user-1",
      email: "student@example.edu",
      created_at: "2026-10-01T00:00:00.000Z",
      last_sign_in_at: "2026-10-05T00:00:00.000Z",
    },
    profile: {
      display_name: "小林",
      real_name: null,
      student_number: null,
    },
    refreshProfile: vi.fn(),
    saveDisplayName: vi.fn(),
    saveProfile: vi.fn(),
    requestEmailChange: vi.fn(),
    logout: vi.fn(),
  },
}));

vi.mock("@/stores/auth", () => ({
  useAuthStore: () => mocks.auth,
}));

vi.mock("@/services/appearance", () => ({
  getAppearancePreference: () => "system",
  saveAppearancePreference: vi.fn(),
}));

import SettingsView from "@/views/SettingsView.vue";

const Dummy = defineComponent({ template: "<div />" });

async function mountView() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/account/settings", name: "account-settings", component: Dummy },
      { path: "/upgrade", name: "upgrade", component: Dummy },
      { path: "/login", name: "login", component: Dummy },
    ],
  });
  await router.push("/account/settings");
  await router.isReady();

  const wrapper = mount(SettingsView, {
    global: {
      plugins: [router],
      stubs: {
        PageState: { template: "<div><slot /></div>" },
        "van-field": {
          props: ["modelValue", "label"],
          template: "<label>{{ label }}<input /></label>",
        },
        "van-button": { template: "<button><slot /></button>" },
      },
    },
  });
  await flushPromises();
  return wrapper;
}

describe("SettingsView upgrade entry", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("links account settings to the global plan and upgrade page", async () => {
    const wrapper = await mountView();
    const link = wrapper.get('a[href="/upgrade"]');

    expect(wrapper.text()).toContain("方案与升级");
    expect(link.text()).toContain("查看方案与升级");
  });
});
