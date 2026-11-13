import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  auth: {
    configured: true,
    loading: false,
    pendingPasswordSetup: false,
    requestSignupCode: vi.fn(),
    verifyPasswordSetupCode: vi.fn(),
    setVerifiedPassword: vi.fn(),
    abortVerifiedAuth: vi.fn(),
  },
  replace: vi.fn(),
  route: { query: {} as Record<string, string> },
  showToast: vi.fn(),
}));

vi.mock("@/stores/auth", () => ({ useAuthStore: () => mocks.auth }));
vi.mock("vue-router", () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock("vant", () => ({ showToast: mocks.showToast }));

import RegisterView from "@/views/RegisterView.vue";

const global = {
  stubs: {
    RouterLink: { props: ["to"], template: "<a><slot /></a>" },
    VanField: {
      props: ["modelValue", "type", "label", "autocomplete", "placeholder"],
      emits: ["update:modelValue"],
      template:
        '<label>{{ label }}<input :type="type" :autocomplete="autocomplete" :placeholder="placeholder" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
    },
    VanButton: {
      props: ["loading", "disabled", "nativeType"],
      template:
        '<button :type="nativeType || \'button\'" :disabled="disabled || loading"><slot /></button>',
    },
  },
};

describe("RegisterView verified password setup", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.auth.configured = true;
    mocks.auth.loading = false;
    mocks.auth.pendingPasswordSetup = false;
    mocks.auth.requestSignupCode.mockResolvedValue({ ok: true });
    mocks.auth.verifyPasswordSetupCode.mockResolvedValue({ ok: true });
    mocks.auth.setVerifiedPassword.mockResolvedValue({ ok: true });
    mocks.route.query = {};
  });

  it("collects email before OTP and does not ask for a password yet", () => {
    const wrapper = mount(RegisterView, { global });

    expect(wrapper.find('input[type="email"]').exists()).toBe(true);
    expect(wrapper.find('input[type="password"]').exists()).toBe(false);
    expect(wrapper.text()).toContain("注册");
  });

  it("moves email → OTP → password and completes account setup", async () => {
    const wrapper = mount(RegisterView, { global });

    await wrapper.get('input[type="email"]').setValue("student@example.edu");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(mocks.auth.requestSignupCode).toHaveBeenCalledWith(
      "student@example.edu",
    );

    await wrapper.get("#otp-code").setValue("123456");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(mocks.auth.verifyPasswordSetupCode).toHaveBeenCalledWith(
      "student@example.edu",
      "123456",
    );

    const passwordInputs = wrapper.findAll('input[type="password"]');
    expect(passwordInputs).toHaveLength(2);
    const passwordInput = passwordInputs[0]!;
    const confirmationInput = passwordInputs[1]!;
    expect(passwordInput.attributes("autocomplete")).toBe("new-password");
    expect(confirmationInput.attributes("autocomplete")).toBe("new-password");
    await passwordInput.setValue("password-1");
    await confirmationInput.setValue("password-1");
    await wrapper.get("form").trigger("submit");
    await flushPromises();

    expect(mocks.auth.setVerifiedPassword).toHaveBeenCalledWith(
      "password-1",
      "password-1",
    );
    expect(mocks.replace).toHaveBeenCalledWith("/projects");
  });

  it("preserves a safe return target after setup", async () => {
    mocks.route.query = { return: "/projects/project-1" };
    const wrapper = mount(RegisterView, { global });
    await wrapper.get('input[type="email"]').setValue("student@example.edu");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    await wrapper.get("#otp-code").setValue("123456");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    const passwordInputs = wrapper.findAll('input[type="password"]');
    await passwordInputs[0]!.setValue("password-1");
    await passwordInputs[1]!.setValue("password-1");
    await wrapper.get("form").trigger("submit");
    await flushPromises();

    expect(mocks.replace).toHaveBeenCalledWith("/projects/project-1");
  });
});
