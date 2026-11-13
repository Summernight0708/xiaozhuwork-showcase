import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => {
  const createdTask = {
    id: "task-1",
    project_id: "project-1",
    version: 1,
    title: "填写表格",
    status: "not_started",
  };
  return {
    createdTask,
    workspace: {
      project: {
        id: "project-1",
        lifecycle_state: "active",
        version: 3,
        contribution_mode: "weighted",
        deadline_at: "2099-12-31T00:00:00.000Z",
      },
      membership: { id: "membership-1", member_state: "active" },
      capabilities: { canCreateTask: true },
      loading: false,
      error: null,
      members: [],
      tasks: [],
      actionError: null as string | null,
      createTask: vi.fn(),
      findTask: vi.fn(),
      setTaskDependencies: vi.fn(),
      inviteTaskCollaborator: vi.fn(),
      uploadFile: vi.fn(),
      markTaskFileReference: vi.fn(),
    },
    reload: vi.fn(),
    replace: vi.fn(),
    push: vi.fn(),
    toast: vi.fn(),
  };
});

vi.mock("@/composables/useWorkspaceRoute", () => ({
  useWorkspaceRoute: () => ({
    workspace: mocks.workspace,
    projectId: { value: "project-1" },
    reload: mocks.reload,
  }),
}));

vi.mock("vue-router", () => ({
  useRouter: () => ({ replace: mocks.replace, push: mocks.push }),
}));

vi.mock("vant", () => ({ showToast: mocks.toast }));

import TaskCreateView from "@/views/TaskCreateView.vue";

const ReferencePickerStub = {
  name: "TaskReferenceFilePicker",
  props: ["modelValue"],
  emits: ["update:modelValue"],
  template: '<div data-test="reference-picker"></div>',
};

function mountView() {
  return mount(TaskCreateView, {
    global: {
      stubs: {
        PageState: { template: "<div><slot /></div>" },
        TaskForm: {
          name: "TaskForm",
          props: ["modelValue", "submitting", "projectDeadlineAt"],
          emits: ["submit", "cancel", "update:modelValue"],
          template:
            '<div><slot name="creation-extras" /><button data-test="submit" @click="$emit(\'submit\')">submit</button></div>',
        },
        TaskReferenceFilePicker: ReferencePickerStub,
      },
    },
  });
}

describe("TaskCreateView reference files", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.workspace.project.lifecycle_state = "active";
    mocks.workspace.project.deadline_at = "2099-12-31T00:00:00.000Z";
    mocks.workspace.capabilities.canCreateTask = true;
    mocks.workspace.membership = {
      id: "membership-1",
      member_state: "active",
    };
    mocks.workspace.createTask.mockResolvedValue({
      ok: true,
      data: { taskId: "task-1", taskVersion: 1 },
    });
    mocks.workspace.findTask.mockReturnValue(mocks.createdTask);
    mocks.workspace.setTaskDependencies.mockResolvedValue({ ok: true });
    mocks.workspace.inviteTaskCollaborator.mockResolvedValue({ ok: true });
    mocks.workspace.uploadFile.mockResolvedValue({
      ok: true,
      data: {
        fileId: "file-1",
        fileVersionId: "file-version-1",
        versionNumber: 1,
      },
    });
    mocks.workspace.markTaskFileReference.mockResolvedValue({ ok: true });
    mocks.reload.mockResolvedValue(undefined);
  });

  it("uploads selected task material and marks it as reference before leaving creation", async () => {
    const wrapper = mountView();
    const taskForm = wrapper.findComponent({ name: "TaskForm" });
    taskForm.vm.$emit("update:modelValue", {
      ...taskForm.props("modelValue"),
      title: "填写表格",
      deadlineAt: "2099-01-01T12:00",
    });
    await wrapper.vm.$nextTick();
    const picker = wrapper.findComponent(ReferencePickerStub);
    expect(picker.exists()).toBe(true);
    if (!picker.exists()) return;

    const file = new File(["template"], "原始表格模板.xlsx", {
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    });
    picker.vm.$emit("update:modelValue", [file]);
    await wrapper.get('[data-test="submit"]').trigger("click");
    await flushPromises();

    expect(mocks.workspace.uploadFile).toHaveBeenCalledWith(
      mocks.createdTask,
      file,
      "new_file",
    );
    expect(mocks.workspace.markTaskFileReference).toHaveBeenCalledWith(
      mocks.createdTask,
      "file-1",
      1,
    );
    expect(mocks.replace).toHaveBeenCalledWith({
      name: "task-detail",
      params: { projectId: "project-1", taskId: "task-1" },
    });
  });

  it("uses the refreshed task version when task setup changes before reference upload", async () => {
    const refreshedTask = { ...mocks.createdTask, version: 4 };
    mocks.workspace.findTask
      .mockReturnValueOnce(mocks.createdTask)
      .mockReturnValue(refreshedTask);

    const wrapper = mountView();
    const taskForm = wrapper.findComponent({ name: "TaskForm" });
    taskForm.vm.$emit("update:modelValue", {
      ...taskForm.props("modelValue"),
      title: "填写表格",
      deadlineAt: "2099-01-01T12:00",
      upstreamTaskIds: ["upstream-1"],
    });
    await wrapper.vm.$nextTick();

    const file = new File(["template"], "原始表格模板.xlsx", {
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    });
    wrapper
      .findComponent(ReferencePickerStub)
      .vm.$emit("update:modelValue", [file]);

    await wrapper.get('[data-test="submit"]').trigger("click");
    await flushPromises();

    expect(mocks.workspace.setTaskDependencies).toHaveBeenCalledWith(
      mocks.createdTask,
      ["upstream-1"],
    );
    expect(mocks.workspace.uploadFile).toHaveBeenCalledWith(
      refreshedTask,
      file,
      "new_file",
    );
  });
});
