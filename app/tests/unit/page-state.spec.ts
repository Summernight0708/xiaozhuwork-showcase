import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import PageState from "@/components/common/PageState.vue";

const global = {
  stubs: {
    VanLoading: { template: "<div><slot /></div>" },
    VanEmpty: {
      props: ["description"],
      template: "<div><span>{{ description }}</span><slot /></div>",
    },
    VanButton: {
      emits: ["click"],
      template: "<button @click='$emit(\"click\")'><slot /></button>",
    },
  },
};

describe("PageState", () => {
  it("renders an explicit loading state", () => {
    const wrapper = mount(PageState, { props: { loading: true }, global });
    expect(wrapper.text()).toContain("正在加载");
  });

  it("renders retryable errors without pretending success", async () => {
    const wrapper = mount(PageState, {
      props: { error: "网络不可用" },
      global,
    });
    expect(wrapper.text()).toContain("网络不可用");
    await wrapper.get("button").trigger("click");
    expect(wrapper.emitted("retry")).toHaveLength(1);
  });

  it("renders permission denied separately from generic errors", () => {
    const wrapper = mount(PageState, {
      props: { permissionDenied: true },
      global,
    });
    expect(wrapper.text()).toContain("没有访问此内容的权限");
  });

  it("renders an existence-safe unavailable state for protected resources", () => {
    const wrapper = mount(PageState, {
      props: { notFoundOrDenied: true },
      global,
    });
    expect(wrapper.text()).toContain("内容不存在，或你没有访问权限");
  });
});
