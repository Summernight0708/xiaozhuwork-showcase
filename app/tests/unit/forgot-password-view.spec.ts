import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  auth: {
    configured: true,
    loading: false,
    pendingPasswordSetup: false,
    requestRecoveryCode: vi.fn(),
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

import ForgotPasswordView from "@/views/ForgotPasswordView.vue";

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

describe("ForgotPasswordView verified reset", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.auth.configured = true;
    mocks.auth.loading = false;
    mocks.auth.pendingPasswordSetup = false;
    mocks.auth.requestRecoveryCode.mockResolvedValue({ ok: true });
    mocks.auth.verifyPasswordSetupCode.mockResolvedValue({ ok: true });
    mocks.auth.setVerifiedPassword.mockResolvedValue({ ok: true });
    mocks.route.query = {};
  });

  it("uses the same non-enumerating response after requesting a recovery code", async () => {
    const wrapper = mount(ForgotPasswordView, { global });
    await wrapper.get('input[type="email"]').setValue("missing@example.edu");
    await wrapper.get("form").trigger("submit");
    await flushPromises();

    expect(mocks.auth.requestRecoveryCode).toHaveBeenCalledWith(
      "missing@example.edu",
    );
    expect(mocks.showToast).toHaveBeenCalledWith(
      "如果该邮箱存在，我们已发送验证码",
    );
    expect(wrapper.find("#otp-code").exists()).toBe(true);
  });

  it("moves OTP → new password and completes recovery", async () => {
    const wrapper = mount(ForgotPasswordView, { global });
    await wrapper.get('input[type="email"]').setValue("student@example.edu");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    await wrapper.get("#otp-code").setValue("123456");
    await wrapper.get("form").trigger("submit");
    await flushPromises();

    const passwordInputs = wrapper.findAll('input[type="password"]');
    await passwordInputs[0]!.setValue("new-password");
    await passwordInputs[1]!.setValue("new-password");
    await wrapper.get("form").trigger("submit");
    await flushPromises();

    expect(mocks.auth.setVerifiedPassword).toHaveBeenCalledWith(
      "new-password",
      "new-password",
    );
    expect(mocks.replace).toHaveBeenCalledWith("/projects");
  });

  it("keeps password fields hidden until OTP verification succeeds", () => {
    const wrapper = mount(ForgotPasswordView, { global });
    expect(wrapper.find('input[type="password"]').exists()).toBe(false);
  });
});
