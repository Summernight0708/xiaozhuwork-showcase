import { mount } from "@vue/test-utils";
import { reactive } from "vue";
import { describe, expect, it, vi } from "vitest";

import type { ProjectEntitlement } from "@/domain/entitlements";

const workspace = reactive({
  project: {
    id: "project-1",
    name: "Team Project",
    course_name: null,
    description: null,
    start_at: null,
    deadline_at: "2026-12-31T00:00:00.000Z",
    timezone: "Asia/Shanghai",
    contribution_mode: "weighted",
    auto_penalty_enabled: false,
    require_real_name: false,
    require_student_number: false,
  },
  membership: { id: "membership-1" },
  members: [],
  tasks: [],
  entitlement: {
    projectId: "project-1",
    plan: "pro",
    state: "active",
    source: "account_member",
    graceExpiresAt: null,
  } as ProjectEntitlement | null,
  capabilities: { canUpdateProjectSettings: false },
  pendingAction: null,
  actionError: null,
  loading: false,
  error: null,
  updateProjectSettings: vi.fn(),
});

vi.mock("@/composables/useWorkspaceRoute", () => ({
  useWorkspaceRoute: () => ({ workspace, reload: vi.fn() }),
}));

import ProjectSettingsView from "@/views/ProjectSettingsView.vue";

function mountView() {
  return mount(ProjectSettingsView, {
    global: {
      stubs: {
        PageState: { template: "<div><slot /></div>" },
        RouterLink: {
          props: ["to"],
          template: '<a :href="to"><slot /></a>',
        },
        "van-button": { template: "<button><slot /></button>" },
      },
    },
  });
}

describe("ProjectSettingsView entitlement display", () => {
  it("shows effective Pro sourced from a project member without exposing an account", () => {
    workspace.entitlement = {
      projectId: "project-1",
      plan: "pro",
      state: "active",
      source: "account_member",
      graceExpiresAt: null,
    };
    const wrapper = mountView();

    expect(wrapper.text()).toContain("项目方案");
    expect(wrapper.text()).toContain("Pro");
    expect(wrapper.text()).toContain("由项目成员 Pro 提供");
    expect(wrapper.text()).not.toContain("购买");
    expect(wrapper.text()).not.toContain("付款");
    expect(wrapper.text()).not.toContain("微信");
    expect(wrapper.get('a[href="/upgrade"]').text()).toContain("了解 Pro");
  });

  it("shows project grace explicitly with its deadline", () => {
    workspace.entitlement = {
      projectId: "project-1",
      plan: "pro",
      state: "grace",
      source: "grace",
      graceExpiresAt: "2026-10-08T08:30:00.000Z",
    };
    const wrapper = mountView();

    expect(wrapper.text()).toContain("Pro · 宽限期");
    expect(wrapper.text()).toContain("宽限至");
    expect(wrapper.text()).toContain("2026");
    expect(wrapper.text()).toContain("现有数据不会被删除");
  });

  it("does not invent a Free project state when entitlement data is unavailable", () => {
    workspace.entitlement = null;
    const wrapper = mountView();

    expect(wrapper.text()).not.toContain("当前项目按 Free 权益运行");
    expect(wrapper.find(".entitlement-section").exists()).toBe(false);
  });

  it("shows Free without implying an entitlement request failure is Free", () => {
    workspace.entitlement = {
      projectId: "project-1",
      plan: "free",
      state: "free",
      source: "none",
      graceExpiresAt: null,
    };
    const wrapper = mountView();

    expect(wrapper.text()).toContain("项目方案");
    expect(wrapper.text()).toContain("Free");
    expect(wrapper.text()).not.toContain("人工开通");
  });
});
