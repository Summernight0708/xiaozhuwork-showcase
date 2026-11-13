import { flushPromises, mount } from "@vue/test-utils";
import { reactive } from "vue";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createProject: vi.fn(),
  updateProjectSettings: vi.fn(),
  leaveProject: vi.fn(),
  confirm: vi.fn(),
  replace: vi.fn(),
}));
const workspace = reactive({
  project: {
    name: "Project",
    course_name: null,
    description: null,
    start_at: null,
    deadline_at: "2099-12-31T00:00:00Z",
    timezone: "Asia/Shanghai",
    contribution_mode: "weighted",
    allow_member_task_creation: true,
    auto_penalty_enabled: false,
    require_real_name: false,
    require_student_number: false,
    lifecycle_state: "active",
  },
  membership: {},
  role: "member",
  currentUserId: "user-1",
  members: [],
  tasks: [] as object[],
  entitlement: null,
  capabilities: { canUpdateProjectSettings: true },
  loading: false,
  error: null,
  actionError: null,
  pendingAction: null,
  updateProjectSettings: mocks.updateProjectSettings,
  leaveProject: mocks.leaveProject,
});
vi.mock("@/composables/useWorkspaceRoute", () => ({
  useWorkspaceRoute: () => ({ workspace, reload: vi.fn() }),
}));
vi.mock("@/stores/projects", () => ({
  useProjectsStore: () => ({ createProject: mocks.createProject }),
}));
vi.mock("vue-router", () => ({
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock("vant", () => ({
  showToast: vi.fn(),
  showConfirmDialog: mocks.confirm,
}));

import ProjectCreateView from "@/views/ProjectCreateView.vue";
import ProjectSettingsView from "@/views/ProjectSettingsView.vue";

const global = {
  stubs: {
    RouterLink: { template: "<a><slot /></a>" },
    PageState: { template: "<div><slot /></div>" },
    "van-button": {
      props: ["nativeType"],
      template: "<button :type=\"nativeType || 'button'\"><slot /></button>",
    },
    "van-field": {
      props: ["modelValue", "name"],
      emits: ["update:modelValue"],
      template:
        '<input :name="name" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
    },
  },
};

beforeEach(() => {
  vi.clearAllMocks();
  workspace.project = {
    ...workspace.project,
    contribution_mode: "weighted",
    allow_member_task_creation: true,
    lifecycle_state: "active",
  };
  workspace.tasks = [];
  workspace.capabilities.canUpdateProjectSettings = true;
  workspace.role = "member";
  workspace.currentUserId = "user-1";
  mocks.createProject.mockResolvedValue({
    ok: true,
    data: { projectId: "new-project" },
  });
  mocks.updateProjectSettings.mockResolvedValue({ ok: true });
  mocks.leaveProject.mockResolvedValue({ ok: true });
  mocks.confirm.mockResolvedValue(undefined);
});

describe("project membership exit", () => {
  it("lets a non-leader leave the project from settings after confirmation", async () => {
    workspace.role = "member";
    workspace.tasks = [];
    const wrapper = mount(ProjectSettingsView, { global });
    const exitButton = wrapper
      .findAll("button")
      .find((button) => button.text() === "退出项目");

    expect(exitButton).toBeDefined();
    if (!exitButton) return;

    await exitButton.trigger("click");
    await flushPromises();

    expect(mocks.confirm).toHaveBeenCalled();
    expect(mocks.leaveProject).toHaveBeenCalledTimes(1);
    expect(mocks.replace).toHaveBeenCalledWith("/projects");
  });

  it("tells the leader to transfer leadership instead of offering direct exit", () => {
    workspace.role = "leader";
    const wrapper = mount(ProjectSettingsView, { global });

    expect(wrapper.text()).toContain("先转让组长");
    expect(
      wrapper.findAll("button").some((button) => button.text() === "退出项目"),
    ).toBe(false);
  });
});

describe("project collaboration checkboxes", () => {
  it.each([true, false])(
    "confirms and submits both creation options as %s",
    async (enabled) => {
      const wrapper = mount(ProjectCreateView, { global });
      for (const name of [
        "allowMemberTaskCreation",
        "enableStarContribution",
      ]) {
        const input = wrapper.get<HTMLInputElement>(`[name="${name}"]`);
        expect(input.element.checked).toBe(true);
        await input.setValue(enabled);
      }
      await wrapper.get('[name="projectName"]').setValue("My project");
      await wrapper.get('[name="deadlineAt"]').setValue("2099-12-31T12:00");
      await wrapper.get("form").trigger("submit");
      expect(wrapper.text()).toContain(enabled ? "允许" : "禁止");
      expect(wrapper.text()).toContain(enabled ? "启用" : "关闭（仅记录事实）");
      await wrapper
        .findAll("button")
        .find((button) => button.text() === "返回修改")!
        .trigger("click");
      expect(
        wrapper.get<HTMLInputElement>('[name="enableStarContribution"]').element
          .checked,
      ).toBe(enabled);
      await wrapper.get("form").trigger("submit");
      await wrapper
        .findAll("button")
        .find((button) => button.text() === "确认创建")!
        .trigger("click");
      await flushPromises();
      expect(mocks.createProject).toHaveBeenCalledWith(
        expect.objectContaining({
          allowMemberTaskCreation: enabled,
          contributionMode: enabled ? "weighted" : "facts_only",
        }),
      );
    },
  );

  it("saves both settings and explains that stars estimate work", async () => {
    const wrapper = mount(ProjectSettingsView, { global });
    await wrapper.get('[name="allowMemberTaskCreation"]').setValue(false);
    await wrapper.get('[name="enableStarContribution"]').setValue(false);
    expect(wrapper.text()).toContain("不是成员评分");
    await wrapper
      .findAll("button")
      .find((button) => button.text() === "保存设置")!
      .trigger("click");
    expect(mocks.updateProjectSettings).toHaveBeenCalledWith(
      expect.objectContaining({
        allowMemberTaskCreation: false,
        contributionMode: "facts_only",
      }),
    );
  });

  it("locks contribution mode for any task while leaving member creation editable", () => {
    workspace.tasks = [{ status: "canceled" }];
    const wrapper = mount(ProjectSettingsView, { global });
    expect(
      wrapper.get<HTMLInputElement>('[name="enableStarContribution"]').element
        .disabled,
    ).toBe(true);
    expect(
      wrapper.get<HTMLInputElement>('[name="allowMemberTaskCreation"]').element
        .disabled,
    ).toBe(false);
    expect(wrapper.text()).toContain("已有任务，不能切换星级贡献统计");
  });

  it.each(["weighted", "facts_only"])(
    "shows %s settings to read-only roles without edit inputs",
    (mode) => {
      workspace.capabilities.canUpdateProjectSettings = false;
      workspace.project.contribution_mode = mode;
      workspace.project.allow_member_task_creation = false;
      const wrapper = mount(ProjectSettingsView, { global });
      expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
      expect(wrapper.text()).not.toContain("保存设置");
      expect(wrapper.text()).toContain("普通成员创建任务：禁止");
      expect(wrapper.text()).toContain(
        mode === "weighted" ? "星级贡献统计：启用" : "关闭（仅记录事实）",
      );
    },
  );
});
