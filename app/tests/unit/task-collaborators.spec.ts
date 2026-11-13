import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { TaskCollaboratorRow, TaskRow } from "@/types/ui";

const task = {
  id: "task-1",
  project_id: "project-1",
  created_by: "creator-1",
  assignee_id: "primary-1",
  assignment_state: "assigned",
  status: "in_progress",
  first_submitted_at: null,
} as TaskRow;

const accepted = {
  id: "collab-accepted",
  project_id: "project-1",
  task_id: "task-1",
  user_id: "collaborator-1",
  user_name_snapshot: "李四",
  state: "accepted",
  version: 2,
} as TaskCollaboratorRow;

const pending = {
  id: "collab-pending",
  project_id: "project-1",
  task_id: "task-1",
  user_id: "current-1",
  user_name_snapshot: "王五",
  state: "pending",
  version: 1,
} as TaskCollaboratorRow;

const workspace = vi.hoisted(() => ({
  role: "member",
  currentUserId: "current-1",
  members: [
    {
      id: "member-primary",
      user_id: "primary-1",
      display_name_snapshot: "张三",
      member_state: "active",
      role: "member",
      is_observer: false,
    },
    {
      id: "member-collab",
      user_id: "collaborator-1",
      display_name_snapshot: "李四",
      member_state: "active",
      role: "member",
      is_observer: false,
    },
    {
      id: "member-current",
      user_id: "current-1",
      display_name_snapshot: "王五",
      member_state: "active",
      role: "member",
      is_observer: false,
    },
    {
      id: "member-other",
      user_id: "member-4",
      display_name_snapshot: "赵六",
      member_state: "active",
      role: "member",
      is_observer: false,
    },
    {
      id: "member-observer",
      user_id: "observer-1",
      display_name_snapshot: "观察者",
      member_state: "active",
      role: "observer",
      is_observer: true,
    },
  ],
  pendingAction: null as string | null,
  collaboratorsForTask: vi.fn(),
  findCollaborator: vi.fn(),
  findTaskChangeProposal: vi.fn(),
  pendingPrimaryHandoff: vi.fn(),
  memberName: vi.fn((id: string | null | undefined) => {
    const names: Record<string, string> = {
      "primary-1": "张三",
      "collaborator-1": "李四",
      "current-1": "王五",
      "member-4": "赵六",
    };
    return id ? names[id] || "成员" : "未分配";
  }),
  inviteTaskCollaborator: vi.fn(),
  respondToTaskCollaborator: vi.fn(),
  removeTaskCollaborator: vi.fn(),
  leaveTaskCollaboration: vi.fn(),
  requestTaskPrimaryHandoff: vi.fn(),
  respondTaskPrimaryHandoff: vi.fn(),
  cancelTaskPrimaryHandoff: vi.fn(),
  unassignTaskPrimary: vi.fn(),
}));

vi.mock("@/stores/workspace", () => ({
  useWorkspaceStore: () => workspace,
}));
vi.mock("vant", () => ({
  showToast: vi.fn(),
  showConfirmDialog: vi.fn().mockResolvedValue(undefined),
}));

import TaskCollaborators from "@/components/task/TaskCollaborators.vue";

function mountComponent() {
  return mount(TaskCollaborators, {
    props: { task },
    global: {
      stubs: {
        "van-button": {
          props: ["loading", "disabled"],
          emits: ["click"],
          template:
            '<button :disabled="disabled || loading" @click="$emit(\'click\')"><slot /></button>',
        },
      },
    },
  });
}

describe("TaskCollaborators", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    workspace.role = "member";
    workspace.currentUserId = "current-1";
    workspace.collaboratorsForTask.mockReturnValue([accepted, pending]);
    workspace.findCollaborator.mockReturnValue(pending);
    workspace.findTaskChangeProposal.mockReturnValue(null);
    workspace.pendingPrimaryHandoff.mockReturnValue(null);
    workspace.inviteTaskCollaborator.mockResolvedValue({ ok: true });
    workspace.respondToTaskCollaborator.mockResolvedValue({ ok: true });
    workspace.removeTaskCollaborator.mockResolvedValue({ ok: true });
    workspace.leaveTaskCollaboration.mockResolvedValue({ ok: true });
    workspace.requestTaskPrimaryHandoff.mockResolvedValue({ ok: true });
    workspace.respondTaskPrimaryHandoff.mockResolvedValue({ ok: true });
    workspace.cancelTaskPrimaryHandoff.mockResolvedValue({ ok: true });
    workspace.unassignTaskPrimary.mockResolvedValue({ ok: true });
  });

  it("keeps responsibility facts in the task header while making management accessible", () => {
    const wrapper = mountComponent();
    expect(wrapper.text()).toContain("管理责任与协作者");
    expect(wrapper.text()).not.toContain("张三");
    expect(wrapper.text()).not.toContain("李四");
    expect(wrapper.text()).toContain("王五");
    expect(wrapper.text()).toContain("待接受");
    expect(wrapper.get("section").attributes("aria-label")).toBe(
      "任务责任管理",
    );
    expect(wrapper.get("details").attributes("open")).toBeDefined();
  });
  it("lets the invitee accept or reject without granting list management", async () => {
    const wrapper = mountComponent();
    const accept = wrapper
      .findAll("button")
      .find((button) => button.text() === "接受协作");
    const reject = wrapper
      .findAll("button")
      .find((button) => button.text() === "拒绝");

    expect(accept).toBeDefined();
    expect(reject).toBeDefined();
    expect(wrapper.text()).not.toContain("邀请协作者");

    await accept!.trigger("click");
    expect(workspace.respondToTaskCollaborator).toHaveBeenCalledWith(
      pending,
      "accept",
    );
  });

  it("lets the task creator manage collaborators but excludes observers from invite candidates", async () => {
    workspace.currentUserId = "creator-1";
    workspace.findCollaborator.mockReturnValue(null);
    const wrapper = mountComponent();

    expect(wrapper.text()).toContain("邀请协作者");
    expect(wrapper.get('select[aria-label="选择协作者"]').text()).toContain(
      "赵六",
    );
    expect(wrapper.get('select[aria-label="选择协作者"]').text()).not.toContain(
      "观察者",
    );

    await wrapper.get('select[aria-label="选择协作者"]').setValue("member-4");
    const invite = wrapper
      .findAll("button")
      .find((button) => button.text() === "邀请协作者");
    await invite!.trigger("click");
    expect(workspace.inviteTaskCollaborator).toHaveBeenCalledWith(
      task,
      "member-4",
    );
  });

  it("lets the current primary transfer or voluntarily unassign to eligible members", async () => {
    workspace.currentUserId = "primary-1";
    workspace.findCollaborator.mockReturnValue(null);
    const wrapper = mountComponent();

    const selector = wrapper.get('select[aria-label="选择新的主负责人"]');
    expect(selector.text()).toContain("李四");
    expect(selector.text()).toContain("赵六");
    expect(selector.text()).not.toContain("观察者");

    await selector.setValue("member-4");
    await wrapper
      .findAll("button")
      .find((button) => button.text() === "发起移交")!
      .trigger("click");
    expect(workspace.requestTaskPrimaryHandoff).toHaveBeenCalledWith(
      task,
      "member-4",
    );

    await wrapper
      .findAll("button")
      .find((button) => button.text() === "卸任并设为待认领")!
      .trigger("click");
    expect(workspace.unassignTaskPrimary).toHaveBeenCalledWith(task);
  });

  it("lets the handoff target accept or reject while the source can cancel", async () => {
    const handoff = {
      id: "handoff-1",
      project_id: "project-1",
      task_id: "task-1",
      from_user_id: "primary-1",
      to_user_id: "current-1",
      from_user_name_snapshot: "张三",
      to_user_name_snapshot: "王五",
      state: "pending",
      version: 1,
    };
    workspace.pendingPrimaryHandoff.mockReturnValue(handoff);
    const wrapper = mountComponent();

    await wrapper
      .findAll("button")
      .find((button) => button.text() === "接受主责")!
      .trigger("click");
    expect(workspace.respondTaskPrimaryHandoff).toHaveBeenCalledWith(
      task,
      handoff,
      "accept",
    );

    wrapper.unmount();
    workspace.currentUserId = "primary-1";
    const sourceWrapper = mountComponent();
    await sourceWrapper
      .findAll("button")
      .find((button) => button.text() === "撤回移交")!
      .trigger("click");
    expect(workspace.cancelTaskPrimaryHandoff).toHaveBeenCalledWith(
      task,
      handoff,
    );
  });

  it("lets an accepted collaborator leave while keeping primary-only semantics separate", async () => {
    workspace.findCollaborator.mockReturnValue(accepted);
    workspace.currentUserId = "collaborator-1";
    const wrapper = mountComponent();

    const leave = wrapper
      .findAll("button")
      .find((button) => button.text() === "退出协作");
    expect(leave).toBeDefined();
    await leave!.trigger("click");
    expect(workspace.leaveTaskCollaboration).toHaveBeenCalledWith(accepted);
  });
});
