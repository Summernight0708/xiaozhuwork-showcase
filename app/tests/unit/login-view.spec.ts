import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  auth: {
    configured: true,
    loading: false,
    loginWithPassword: vi.fn(),
  },
  replace: vi.fn(),
  route: { query: {} as Record<string, string> },
  showToast: vi.fn(),
}));

vi.mock("@/stores/auth", () => ({
  useAuthStore: () => mocks.auth,
}));

vi.mock("vue-router", () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));

vi.mock("vant", () => ({
  showToast: mocks.showToast,
}));

import LoginView from "@/views/LoginView.vue";

const global = {
  stubs: {
    RouterLink: {
      props: ["to"],
      template: "<a data-router-link><slot /></a>",
    },
    VanField: {
      props: ["modelValue", "type", "label", "autocomplete", "placeholder"],
      emits: ["update:modelValue"],
      template:
        '<label>{{ label }}<input :type="type" :autocomplete="autocomplete" :placeholder="placeholder" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
    },
    VanButton: {
      props: ["loading", "disabled", "nativeType"],
      template:
        '<button :type="nativeType || \'button\'" :disabled="disabled || loading" :aria-busy="loading ? \'true\' : undefined"><slot /></button>',
    },
  },
};

function mountLogin() {
  return mount(LoginView, { global });
}

describe("LoginView password entry", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.auth.configured = true;
    mocks.auth.loading = false;
    mocks.auth.loginWithPassword.mockResolvedValue({
      ok: true,
      user: { id: "user-1" },
      session: { access_token: "token" },
    });
    mocks.route.query = {};
  });

  it("keeps the product positioning while making password login the only login form", () => {
    const wrapper = mountLogin();

    expect(wrapper.get(".brand-name").text()).toBe("小猪作业");
    expect(wrapper.text()).toContain("让小组作业更清楚");
    expect(wrapper.get('input[type="email"]').attributes("autocomplete")).toBe(
      "email",
    );
    expect(
      wrapper.get('input[type="password"]').attributes("autocomplete"),
    ).toBe("current-password");
    expect(wrapper.find("#otp-code").exists()).toBe(false);
    expect(wrapper.text()).toContain("忘记密码");
    expect(wrapper.text()).toContain("注册");
    expect(wrapper.text()).not.toContain("密码由认证服务安全管理");
    expect(wrapper.text()).not.toContain("下载 Android 客户端");
  });

  it("logs in with email/password and preserves a safe return target", async () => {
    mocks.route.query = { return: "/projects/project-1/tasks/task-1" };
    const wrapper = mountLogin();

    await wrapper.get('input[type="email"]').setValue("student@example.edu");
    await wrapper.get('input[type="password"]').setValue("password-1");
    await wrapper.get("form").trigger("submit");
    await flushPromises();

    expect(mocks.auth.loginWithPassword).toHaveBeenCalledWith(
      "student@example.edu",
      "password-1",
    );
    expect(mocks.replace).toHaveBeenCalledWith(
      "/projects/project-1/tasks/task-1",
    );
  });

  it("falls back to projects for an unsafe return target", async () => {
    mocks.route.query = { return: "//evil.example" };
    const wrapper = mountLogin();

    await wrapper.get('input[type="email"]').setValue("student@example.edu");
    await wrapper.get('input[type="password"]').setValue("password-1");
    await wrapper.get("form").trigger("submit");
    await flushPromises();

    expect(mocks.replace).toHaveBeenCalledWith("/projects");
  });

  it("uses one enumeration-safe message for invalid credentials", async () => {
    mocks.auth.loginWithPassword.mockResolvedValue({
      ok: false,
      code: "INVALID_CREDENTIALS",
    });
    const wrapper = mountLogin();

    await wrapper.get('input[type="email"]').setValue("student@example.edu");
    await wrapper.get('input[type="password"]').setValue("wrong-pass");
    await wrapper.get("form").trigger("submit");
    await flushPromises();

    expect(mocks.showToast).toHaveBeenCalledWith("邮箱或密码错误");
  });

  it("shows a user-facing unavailable state without leaking internal env names", () => {
    mocks.auth.configured = false;
    const wrapper = mountLogin();
    const alert = wrapper.get('[role="alert"]');

    expect(alert.text()).toContain("登录服务暂时不可用");
    expect(alert.text()).not.toContain("VITE_SUPABASE");
    expect(wrapper.get('button[type="submit"]').attributes()).toHaveProperty(
      "disabled",
    );
  });
});
