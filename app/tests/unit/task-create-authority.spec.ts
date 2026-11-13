import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => {
  const workspace = {
    project: {
      id: "project-1",
      lifecycle_state: "active",
      version: 3,
      contribution_mode: "weighted",
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
  };
  return {
    workspace,
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

vi.mock("vant", () => ({
  showToast: mocks.toast,
}));

vi.mock("@/domain/task-form", () => ({
  emptyTaskForm: () => ({
    title: "Authority refresh task",
    description: "",
    deadlineAt: "2099-10-10T12:00",
    difficulty: 3,
    assignmentMode: "claimable",
    assigneeId: "",
    collaboratorIds: [],
    upstreamTaskIds: [],
    requiredFileTypes: [],
  }),
  validateTaskForm: () => null,
}));

import TaskCreateView from "@/views/TaskCreateView.vue";

function mountView() {
  return mount(TaskCreateView, {
    global: {
      stubs: {
        PageState: { template: "<div><slot /></div>" },
        TaskForm: {
          props: ["modelValue", "submitting"],
          emits: ["submit", "cancel", "update:modelValue"],
          template:
            '<button data-test="submit" @click="$emit(\'submit\')">submit</button>',
        },
      },
    },
  });
}

describe("TaskCreateView authority refresh", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.workspace.project = {
      id: "project-1",
      lifecycle_state: "active",
      version: 3,
      contribution_mode: "weighted",
    };
    mocks.workspace.membership = {
      id: "membership-1",
      member_state: "active",
    };
    mocks.workspace.capabilities = { canCreateTask: true };
    mocks.workspace.actionError = null;
    mocks.workspace.createTask.mockResolvedValue({
      ok: false,
      code: "STALE_VERSION",
      requestId: "request-1",
      replayed: false,
      currentVersion: 4,
    });
    mocks.reload.mockResolvedValue(undefined);
  });

  it("refreshes membership authority before issuing create", async () => {
    mocks.reload.mockImplementation(async () => {
      mocks.workspace.membership = null as never;
      mocks.workspace.capabilities = { canCreateTask: false };
    });
    const wrapper = mountView();

    await wrapper.get('[data-test="submit"]').trigger("click");
    await vi.waitFor(() => expect(mocks.reload).toHaveBeenCalledTimes(1));

    expect(mocks.workspace.createTask).not.toHaveBeenCalled();
    expect(mocks.toast).toHaveBeenCalledWith(
      "你当前没有在此项目创建任务的权限，成员身份可能已变化。",
    );
  });

  it("creates only after the authoritative refresh keeps permission", async () => {
    const wrapper = mountView();

    await wrapper.get('[data-test="submit"]').trigger("click");
    await vi.waitFor(() =>
      expect(mocks.workspace.createTask).toHaveBeenCalledTimes(1),
    );

    expect(mocks.reload.mock.invocationCallOrder[0]).toBeLessThan(
      mocks.workspace.createTask.mock.invocationCallOrder[0]!,
    );
  });

  it("omits star weight when the refreshed project uses facts only", async () => {
    mocks.reload.mockImplementation(async () => {
      mocks.workspace.project.contribution_mode = "facts_only";
    });
    const wrapper = mountView();
    await wrapper.get('[data-test="submit"]').trigger("click");
    await vi.waitFor(() =>
      expect(mocks.workspace.createTask).toHaveBeenCalledTimes(1),
    );
    expect(
      mocks.workspace.createTask.mock.calls[0]?.[0].weight,
    ).toBeUndefined();
  });

  it("blocks submission when the member creation setting changes during refresh", async () => {
    mocks.reload.mockImplementation(async () => {
      mocks.workspace.capabilities.canCreateTask = false;
    });
    const wrapper = mountView();
    await wrapper.get('[data-test="submit"]').trigger("click");
    await vi.waitFor(() => expect(mocks.reload).toHaveBeenCalledTimes(1));
    expect(mocks.workspace.createTask).not.toHaveBeenCalled();
  });
});
