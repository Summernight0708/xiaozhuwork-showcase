import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const task = {
  id: "task-1",
  project_id: "project-1",
  title: "Accepted task",
  description: null,
  deadline_at: "2026-10-05T12:00:00Z",
  weight: 3,
  assignment_state: "assigned",
  status: "in_progress",
  assignee_id: "assignee-1",
  accepted_at: "2026-09-30T00:00:00Z",
  completed_at: null,
  progress_text: "",
  blocked_reason: null,
  created_by: "creator-1",
  created_at: "2026-09-29T00:00:00Z",
  updated_at: "2026-09-30T00:00:00Z",
  version: 3,
};

const proposal = {
  id: "proposal-1",
  project_id: "project-1",
  task_id: "task-1",
  proposed_by: "creator-1",
  proposer_name_snapshot: "创建者",
  state: "pending",
  old_deadline_at: "2026-10-05T12:00:00Z",
  new_deadline_at: "2026-10-07T12:00:00Z",
  old_weight: 3,
  new_weight: 4,
  base_task_version: 3,
  required_confirmer_id: "assignee-1",
  required_confirmer_name_snapshot: "负责人",
  decided_at: null,
  decided_by: null,
  decision_reason: null,
  version: 1,
  created_at: "2026-10-01T01:00:00Z",
  updated_at: "2026-10-01T01:00:00Z",
};

const workspace = vi.hoisted(() => ({
  loading: false,
  error: null,
  project: { id: "project-1", contribution_mode: "weighted" },
  membership: { id: "membership-1" },
  role: "member",
  currentUserId: "assignee-1",
  reviews: [],
  reviewFiles: [],
  taskFiles: {},
  tasks: [] as unknown[],
  actionError: null,
  pendingAction: null,
  capabilities: { canUploadFile: false, canReviewSubmission: false },
  findTask: vi.fn(),
  findTaskChangeProposal: vi.fn(),
  findOffer: vi.fn().mockReturnValue(null),
  isTaskParticipant: vi.fn().mockReturnValue(false),
  isAcceptedCollaborator: vi.fn().mockReturnValue(false),
  memberName: vi.fn().mockReturnValue("成员"),
  upstreamTasks: vi.fn().mockReturnValue([]),
  downstreamTasks: vi.fn().mockReturnValue([]),
  dependencyState: vi.fn().mockReturnValue({
    blocked: false,
    upstreamCount: 0,
    incompleteUpstreamCount: 0,
    effectiveStartAt: null,
  }),
  taskDisplayStatus: vi.fn((item: { status: string }) => item.status),
  loadBase: vi.fn().mockResolvedValue(undefined),
  loadTaskFiles: vi.fn().mockResolvedValue([]),
  loadReviews: vi.fn().mockResolvedValue(undefined),
  proposeTaskChange: vi.fn().mockResolvedValue({ ok: true }),
  respondToTaskChange: vi.fn().mockResolvedValue({ ok: true }),
  setTaskDependencies: vi.fn(),
  submitReview: vi.fn(),
}));

const taskWorkflow = vi.hoisted(() => ({
  load: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("@/stores/task-workflow", () => ({
  useTaskWorkflowStore: () => taskWorkflow,
}));
vi.mock("@/components/task/TaskHelpPanel.vue", () => ({
  default: { template: "<div />" },
}));
vi.mock("@/components/task/UpstreamReworkPanel.vue", () => ({
  default: { template: "<div />" },
}));
vi.mock("@/stores/workspace", () => ({ useWorkspaceStore: () => workspace }));
vi.mock("@/components/common/PageState.vue", () => ({
  default: { template: "<div><slot /></div>" },
}));
vi.mock("@/components/common/StatusBadge.vue", () => ({
  default: { props: ["status"], template: "<span>{{ status }}</span>" },
}));

import TaskDetailContent from "@/components/task/TaskDetailContent.vue";

function mountView() {
  return mount(TaskDetailContent, {
    props: { projectId: "project-1", taskId: "task-1" },
    global: {
      stubs: {
        "van-button": {
          props: ["loading"],
          template: "<button @click='$emit(\"click\")'><slot /></button>",
        },
        "van-field": {
          props: ["modelValue"],
          template: "<input />",
        },
        TaskCollaborators: { template: "<div />" },
      },
    },
  });
}

describe("task change confirmation view", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    workspace.findTask.mockReturnValue(task);
    workspace.findTaskChangeProposal.mockReturnValue(proposal);
    workspace.tasks = [task];
    workspace.currentUserId = "assignee-1";
    workspace.role = "member";
  });

  it("shows authoritative old/new facts and decision actions to the current assignee", () => {
    const wrapper = mountView();
    expect(wrapper.text()).toContain("待确认变更");
    expect(wrapper.text()).toContain("等待负责人确认");
    expect(wrapper.text()).toContain("创建者");
    expect(wrapper.text()).toContain("批准");
    expect(wrapper.text()).toContain("拒绝");
    expect(wrapper.text()).toContain("4 星");
  });

  it("keeps unrelated members read-only", () => {
    workspace.currentUserId = "other-1";
    const wrapper = mountView();
    expect(wrapper.text()).toContain("其他成员仅可查看");
    expect(
      wrapper.findAll("button").some((button) => button.text() === "批准"),
    ).toBe(false);
    expect(
      wrapper.findAll("button").some((button) => button.text() === "拒绝"),
    ).toBe(false);
  });

  it("lets the task creator start the server proposal workflow", async () => {
    workspace.findTaskChangeProposal.mockReturnValue(null);
    workspace.currentUserId = "creator-1";
    workspace.role = "member";
    const wrapper = mountView();
    const propose = wrapper
      .findAll("button")
      .find((button) => button.text() === "发起变更确认");
    expect(propose).toBeTruthy();
    await propose!.trigger("click");
    expect(workspace.proposeTaskChange).toHaveBeenCalled();
  });

  it("exposes the proposal flow when work facts exist before accepted_at", () => {
    workspace.findTaskChangeProposal.mockReturnValue(null);
    workspace.findTask.mockReturnValue({
      ...task,
      accepted_at: null,
      status: "not_started",
      progress_text: "work already started",
    });
    workspace.currentUserId = "creator-1";
    workspace.role = "member";
    const wrapper = mountView();
    expect(
      wrapper
        .findAll("button")
        .some((button) => button.text() === "发起变更确认"),
    ).toBe(true);
  });

  it("lets the project leader propose without becoming the confirmer", () => {
    workspace.findTaskChangeProposal.mockReturnValue(null);
    workspace.currentUserId = "leader-1";
    workspace.role = "leader";
    const wrapper = mountView();
    expect(
      wrapper
        .findAll("button")
        .some((button) => button.text() === "发起变更确认"),
    ).toBe(true);
    expect(
      wrapper.findAll("button").some((button) => button.text() === "批准"),
    ).toBe(false);
  });

  it("lets the responsibility holder invoke the server decision workflow", async () => {
    const wrapper = mountView();
    const approve = wrapper
      .findAll("button")
      .find((button) => button.text() === "批准");
    expect(approve).toBeTruthy();
    await approve!.trigger("click");
    expect(workspace.respondToTaskChange).toHaveBeenCalledWith(
      proposal,
      "approve",
      undefined,
    );
  });
});
