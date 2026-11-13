import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const showToast = vi.hoisted(() => vi.fn());

const currentTask = {
  id: "task-down",
  project_id: "project-1",
  title: "Current task",
  description: null,
  deadline_at: "2026-10-10T00:00:00Z",
  weight: 2,
  assignment_state: "assigned",
  status: "in_progress",
  assignee_id: "member-1",
  accepted_at: "2026-10-01T00:00:00Z",
  completed_at: null,
  first_submitted_at: null,
  progress_text: "",
  blocked_reason: null,
  created_by: "leader-1",
  created_at: "2026-10-01T00:00:00Z",
  updated_at: "2026-10-01T00:00:00Z",
  version: 3,
};

const completedUpstream = {
  ...currentTask,
  id: "task-up-complete",
  title: "Completed upstream",
  status: "completed",
  assignee_id: "upstream-owner",
  completed_at: "2026-10-02T00:00:00Z",
  version: 5,
};

const activeUpstream = {
  ...currentTask,
  id: "task-up-active",
  title: "Active upstream",
  status: "in_progress",
  assignee_id: "other-1",
  version: 2,
};

const helpRequest = {
  id: "help-1",
  project_id: "project-1",
  task_id: "task-down",
  requested_by: "member-1",
  target_user_id: "helper-1",
  message: "Need help",
  marks_task_blocked: true,
  blocked_task_version: 4,
  state: "open",
  resolved_by: null,
  resolved_at: null,
  version: 1,
  created_at: "2026-10-03T00:00:00Z",
  updated_at: "2026-10-03T00:00:00Z",
};

const reworkRequest = {
  id: "rework-1",
  project_id: "project-1",
  downstream_task_id: "task-down",
  upstream_task_id: "task-up-complete",
  requested_by: "member-1",
  requirement: "Please revise",
  state: "pending",
  upstream_completed_version: 5,
  reviewed_by: null,
  reviewed_at: null,
  version: 1,
  created_at: "2026-10-03T00:00:00Z",
  updated_at: "2026-10-03T00:00:00Z",
};

const workspace = vi.hoisted(() => ({
  loading: false,
  error: null,
  project: { id: "project-1", contribution_mode: "weighted" },
  membership: { id: "membership-1" },
  role: "member",
  currentUserId: "member-1",
  reviews: [],
  reviewFiles: [],
  taskFiles: {} as Record<string, unknown[]>,
  tasks: [] as unknown[],
  members: [
    { user_id: "leader-1", role: "leader", member_state: "active" },
    { user_id: "member-1", role: "member", member_state: "active" },
    { user_id: "helper-1", role: "member", member_state: "active" },
    { user_id: "observer-1", role: "observer", member_state: "active" },
  ],
  actionError: null,
  pendingAction: null as string | null,
  capabilities: { canUploadFile: false, canReviewSubmission: false },
  findTask: vi.fn(),
  findTaskChangeProposal: vi.fn().mockReturnValue(null),
  findOffer: vi.fn().mockReturnValue(null),
  isTaskParticipant: vi.fn(),
  isAcceptedCollaborator: vi.fn().mockReturnValue(false),
  memberName: vi.fn((id: string) => id),
  upstreamTasks: vi.fn(),
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
  refreshTasks: vi.fn().mockResolvedValue(undefined),
  setTaskDependencies: vi.fn(),
  proposeTaskChange: vi.fn(),
  respondToTaskChange: vi.fn(),
  submitReview: vi.fn(),
}));

const workflow = vi.hoisted(() => ({
  helpRequests: [] as (typeof helpRequest)[],
  reworkRequests: [] as (typeof reworkRequest)[],
  loading: false,
  error: null as string | null,
  actionError: null as string | null,
  pendingAction: null as string | null,
  load: vi.fn().mockResolvedValue(undefined),
  createHelp: vi.fn().mockResolvedValue({
    ok: true,
    data: {
      helpRequestId: "help-new",
      state: "open",
      helpVersion: 1,
      taskVersion: 3,
      taskResumed: false,
    },
  }),
  resolveHelp: vi.fn().mockResolvedValue({
    ok: true,
    data: {
      helpRequestId: "help-1",
      state: "resolved",
      helpVersion: 2,
      taskVersion: 5,
      taskResumed: false,
    },
  }),
  requestRework: vi.fn().mockResolvedValue({
    ok: true,
    data: {
      reworkRequestId: "rework-new",
      state: "pending",
      requestVersion: 1,
      downstreamTaskVersion: 3,
      upstreamTaskVersion: 5,
    },
  }),
  reviewRework: vi.fn().mockResolvedValue({
    ok: true,
    data: {
      reworkRequestId: "rework-1",
      state: "approved",
      requestVersion: 2,
      downstreamTaskVersion: 3,
      upstreamTaskVersion: 6,
    },
  }),
}));

vi.mock("vant", () => ({ showToast }));
vi.mock("@/stores/workspace", () => ({ useWorkspaceStore: () => workspace }));
vi.mock("@/stores/task-workflow", () => ({
  useTaskWorkflowStore: () => workflow,
}));
vi.mock("@/components/common/PageState.vue", () => ({
  default: { template: "<div><slot /></div>" },
}));
vi.mock("@/components/common/StatusBadge.vue", () => ({
  default: { props: ["status"], template: "<span>{{ status }}</span>" },
}));

import TaskDetailContent from "@/components/task/TaskDetailContent.vue";
import TaskHelpPanel from "@/components/task/TaskHelpPanel.vue";
import UpstreamReworkPanel from "@/components/task/UpstreamReworkPanel.vue";

const buttonStub = {
  props: ["loading", "disabled"],
  emits: ["click"],
  template: `<button :disabled="disabled" @click="$emit('click')"><slot /></button>`,
};

function mountHelp() {
  return mount(TaskHelpPanel, {
    props: { projectId: "project-1", taskId: "task-down" },
    global: { stubs: { "van-button": buttonStub } },
  });
}

function mountRework() {
  return mount(UpstreamReworkPanel, {
    props: { projectId: "project-1", taskId: "task-down" },
    global: { stubs: { "van-button": buttonStub } },
  });
}

describe("task help and upstream rework view", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    workspace.role = "member";
    workspace.currentUserId = "member-1";
    workspace.isTaskParticipant.mockImplementation(
      (item: { assignee_id?: string | null }) =>
        item.assignee_id === workspace.currentUserId ||
        workspace.isAcceptedCollaborator(
          item === currentTask ? "task-down" : "",
        ),
    );
    workspace.findTask.mockImplementation((id: string) => {
      if (id === currentTask.id) return currentTask;
      if (id === completedUpstream.id) return completedUpstream;
      if (id === activeUpstream.id) return activeUpstream;
      return undefined;
    });
    workspace.upstreamTasks.mockReturnValue([
      completedUpstream,
      activeUpstream,
    ]);
    workspace.tasks = [currentTask, completedUpstream, activeUpstream];
    workspace.taskFiles = {};
    workspace.findTaskChangeProposal.mockReturnValue(null);
    workspace.pendingAction = null;
    workflow.helpRequests = [];
    workflow.reworkRequests = [];
    workflow.pendingAction = null;
    workflow.error = null;
    workflow.actionError = null;
  });

  it("shows help creation only to the current assignee and defaults to the leader", () => {
    const assignee = mountHelp();
    expect(assignee.text()).toContain("发起求助");
    expect(assignee.text()).toContain("默认通知组长");

    workspace.currentUserId = "other-1";
    const unrelated = mountHelp();
    expect(unrelated.text()).toContain(
      "只有当前任务的主负责人或已接受协作者可以发起求助",
    );
    expect(
      unrelated
        .findAll("button")
        .some((button) => button.text() === "发起求助"),
    ).toBe(false);
  });

  it("allows requester, target or leader to resolve and explains retained blocking", async () => {
    workflow.helpRequests = [helpRequest];

    workspace.currentUserId = "helper-1";
    const helper = mountHelp();
    const resolve = helper
      .findAll("button")
      .find((button) => button.text() === "标记已解决");
    expect(resolve).toBeTruthy();
    await resolve!.trigger("click");
    await flushPromises();
    expect(workflow.resolveHelp).toHaveBeenCalledWith(helpRequest);
    expect(showToast).toHaveBeenCalledWith(
      expect.stringContaining("当前阻塞状态保留"),
    );

    workspace.currentUserId = "other-1";
    workspace.role = "member";
    const unrelated = mountHelp();
    expect(
      unrelated
        .findAll("button")
        .some((button) => button.text() === "标记已解决"),
    ).toBe(false);

    workspace.role = "leader";
    const leader = mountHelp();
    expect(
      leader.findAll("button").some((button) => button.text() === "标记已解决"),
    ).toBe(true);
  });

  it("offers rework only for completed direct upstream tasks", () => {
    const wrapper = mountRework();
    expect(wrapper.text()).toContain("申请上游返工");
    expect(wrapper.text()).toContain("Completed upstream");
    expect(wrapper.text()).not.toContain("Active upstream");
  });

  it("shows pending rework decisions only to the leader", () => {
    workflow.reworkRequests = [reworkRequest];

    const member = mountRework();
    expect(member.text()).toContain("待组长处理");
    expect(
      member.findAll("button").some((button) => button.text() === "批准返工"),
    ).toBe(false);

    workspace.role = "leader";
    workspace.currentUserId = "leader-1";
    const leader = mountRework();
    expect(
      leader.findAll("button").some((button) => button.text() === "批准返工"),
    ).toBe(true);
    expect(
      leader.findAll("button").some((button) => button.text() === "拒绝"),
    ).toBe(true);
  });

  it("disables workflow actions while another workflow command is pending", () => {
    workflow.pendingAction = "create-help";
    const help = mountHelp();
    const create = help
      .findAll("button")
      .find((button) => button.text() === "发起求助");
    expect(create?.attributes("disabled")).toBeDefined();

    workflow.pendingAction = "request-rework:task-up-complete";
    const rework = mountRework();
    const request = rework
      .findAll("button")
      .find((button) => button.text() === "申请上游返工");
    expect(request?.attributes("disabled")).toBeDefined();
  });

  it("mounts the integrated Task Detail sections and keeps task-file preview as an outward event", async () => {
    workspace.taskFiles = {
      "task-down": [
        {
          fileId: "file-1",
          logicalName: "deliverable.pdf",
          currentVersionId: "file-version-1",
          versions: [
            {
              fileVersionId: "file-version-1",
              originalName: "deliverable.pdf",
              mimeType: "application/pdf",
              sizeBytes: 1024,
              versionNumber: 1,
              uploadedBy: "member-1",
              createdAt: "2026-10-03T00:00:00Z",
            },
          ],
        },
      ],
    };
    workspace.findTaskChangeProposal.mockReturnValue({
      id: "proposal-1",
      task_id: "task-down",
      state: "pending",
      required_confirmer_id: "member-1",
      old_deadline_at: "2026-10-10T00:00:00Z",
      new_deadline_at: "2026-10-11T00:00:00Z",
      old_weight: 2,
      new_weight: 3,
      old_required_submission_file_type: null,
      old_required_submission_file_types: [],
      new_required_submission_file_type: "pdf",
      new_required_submission_file_types: ["pdf"],
      proposer_name_snapshot: "leader-1",
      proposed_by: "leader-1",
      created_at: "2026-10-03T00:00:00Z",
    });

    const wrapper = mount(TaskDetailContent, {
      props: { projectId: "project-1", taskId: "task-down" },
      global: {
        stubs: {
          "van-button": buttonStub,
          "van-field": { template: "<div />" },
          TaskCollaborators: { template: "<div>任务责任协作区</div>" },
          TaskSubmissionPanel: { template: "<div>统一提交区</div>" },
          TaskReviewHistory: { template: "<div>验收历史区</div>" },
          UpstreamArtifacts: { template: "<div>上游成果区</div>" },
          TaskHelpPanel: { template: "<div>任务求助面板</div>" },
          UpstreamReworkPanel: { template: "<div>上游返工面板</div>" },
          FilePreviewPanel: {
            emits: ["preview-success"],
            template:
              "<button class=\"task-file-preview-stub\" @click=\"$emit('preview-success', 'file-version-1')\">文件预览区</button>",
          },
        },
      },
    });
    await flushPromises();

    expect(wrapper.text()).toContain("任务责任协作区");
    expect(wrapper.text()).toContain("统一提交区");
    expect(wrapper.text()).toContain("验收历史区");
    expect(wrapper.text()).toContain("上游成果区");
    expect(wrapper.text()).toContain("任务求助面板");
    expect(wrapper.text()).toContain("上游返工面板");
    expect(wrapper.text()).toContain("上下游");
    expect(wrapper.text()).toContain("待确认变更");
    expect(wrapper.text()).toContain("任务文件");
    expect(wrapper.emitted("file-preview-success")).toBeUndefined();

    await wrapper
      .get('button[aria-label="预览任务文件 deliverable.pdf"]')
      .trigger("click");
    await wrapper.get(".task-file-preview-stub").trigger("click");
    expect(wrapper.emitted("file-preview-success")).toBeUndefined();
    expect(workflow.load).toHaveBeenCalledWith("project-1", "task-down", true);
  });
});
