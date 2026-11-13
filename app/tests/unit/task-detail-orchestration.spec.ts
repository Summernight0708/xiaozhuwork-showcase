import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const task = {
  id: "task-1",
  project_id: "project-1",
  title: "数据分析",
  description: "整理数据",
  deadline_at: "2026-10-06T10:00:00Z",
  weight: 3,
  assignment_state: "assigned",
  status: "in_progress",
  assignee_id: "user-1",
  accepted_at: "2026-10-01T00:00:00Z",
  first_submitted_at: null,
  completed_at: null,
  progress_text: "",
  blocked_reason: null,
  created_by: "leader-1",
  created_at: "2026-09-30T00:00:00Z",
  updated_at: "2026-10-01T00:00:00Z",
  version: 1,
};

const workspace = vi.hoisted(() => ({
  loading: false,
  error: null,
  project: { id: "project-1", contribution_mode: "weighted" },
  membership: { id: "membership-1" },
  role: "member",
  currentUserId: "user-1",
  reviews: [],
  taskFiles: {},
  tasks: [] as unknown[],
  files: [],
  fileVersions: [],
  fileFinalDesignations: [],
  actionError: null,
  pendingAction: null,
  capabilities: { canUploadFile: true, canReviewSubmission: false },
  findTask: vi.fn(),
  findTaskChangeProposal: vi.fn().mockReturnValue(null),
  findOffer: vi.fn().mockReturnValue(null),
  memberName: vi.fn().mockReturnValue("张三"),
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
  loadFiles: vi.fn().mockResolvedValue(undefined),
  setTaskDependencies: vi.fn(),
  proposeTaskChange: vi.fn(),
  respondToTaskChange: vi.fn(),
  editTask: vi.fn(),
  updateTaskProgress: vi.fn(),
  uploadFile: vi.fn(),
  claimTask: vi.fn(),
  respondToAssignment: vi.fn(),
}));

vi.mock("@/stores/workspace", () => ({
  useWorkspaceStore: () => workspace,
}));
vi.mock("@/components/common/PageState.vue", () => ({
  default: { template: "<div><slot /></div>" },
}));
vi.mock("@/stores/task-workflow", () => ({
  useTaskWorkflowStore: () => ({
    helpRequests: [],
    reworkRequests: [],
    load: vi.fn().mockResolvedValue(undefined),
  }),
}));

import TaskDetailContent from "@/components/task/TaskDetailContent.vue";

describe("task detail orchestration shell", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    workspace.findTask.mockReturnValue(task);
    workspace.tasks = [task];
  });

  it("exposes exactly the five approved top-level groups", () => {
    const wrapper = mount(TaskDetailContent, {
      props: { projectId: "project-1", taskId: "task-1" },
      global: {
        stubs: {
          "van-button": { template: "<button><slot /></button>" },
          "van-field": { template: "<div />" },
          TaskCollaborators: { template: "<div />" },
          TaskSubmissionPanel: { template: "<div />" },
          TaskReviewHistory: { template: "<div />" },
          UpstreamArtifacts: { template: "<div />" },
          TaskHelpPanel: { template: "<div />" },
          UpstreamReworkPanel: { template: "<div />" },
          FilePreviewPanel: { template: "<div />" },
        },
      },
    });

    const topLevelLabels = wrapper
      .findAll(".section-toggle")
      .map((button) => button.text().replace(/[▾▸]/g, "").trim());

    expect(topLevelLabels).toEqual([
      "概况",
      "提交与文件",
      "上下游",
      "协作与问题",
      "历史与变更",
    ]);
  });
});
