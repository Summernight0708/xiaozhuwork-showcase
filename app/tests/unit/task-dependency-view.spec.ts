import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";

const task = {
  id: "task-c",
  project_id: "project-1",
  title: "Current task",
  description: "Current description",
  deadline_at: "2026-10-10T00:00:00Z",
  weight: 2,
  assignment_state: "assigned",
  status: "in_progress",
  assignee_id: "user-1",
  accepted_at: null,
  completed_at: null,
  progress_text: "",
  blocked_reason: null,
  created_by: "leader-1",
  created_at: "2026-09-30T00:00:00Z",
  updated_at: "2026-09-30T00:00:00Z",
  version: 1,
};
const upstream = {
  ...task,
  id: "task-a",
  title: "Alpha",
  status: "in_progress",
};
const downstream = {
  ...task,
  id: "task-d",
  title: "Delta",
  status: "not_started",
};

const workspace = vi.hoisted(() => ({
  loading: false,
  error: null,
  project: { id: "project-1", contribution_mode: "weighted" },
  membership: { id: "membership-1" },
  role: "leader",
  currentUserId: "leader-1",
  reviews: [],
  reviewFiles: [],
  taskFiles: {},
  tasks: [] as unknown[],
  actionError: null,
  pendingAction: null,
  capabilities: { canUploadFile: false, canReviewSubmission: false },
  findTask: vi.fn(),
  findTaskChangeProposal: vi.fn().mockReturnValue(null),
  findOffer: vi.fn().mockReturnValue(null),
  isTaskParticipant: vi.fn().mockReturnValue(false),
  isAcceptedCollaborator: vi.fn().mockReturnValue(false),
  memberName: vi.fn().mockReturnValue("Member"),
  upstreamTasks: vi.fn(),
  downstreamTasks: vi.fn(),
  dependencyState: vi.fn(),
  taskDisplayStatus: vi.fn((item: { status: string }) => item.status),
  loadBase: vi.fn().mockResolvedValue(undefined),
  loadTaskFiles: vi.fn().mockResolvedValue([]),
  loadReviews: vi.fn().mockResolvedValue(undefined),
  setTaskDependencies: vi.fn(),
  proposeTaskChange: vi.fn(),
  respondToTaskChange: vi.fn(),
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
vi.mock("@/stores/workspace", () => ({
  useWorkspaceStore: () => workspace,
}));
vi.mock("@/components/common/PageState.vue", () => ({
  default: { template: "<div><slot /></div>" },
}));
vi.mock("@/components/common/StatusBadge.vue", () => ({
  default: { props: ["status"], template: "<span>{{ status }}</span>" },
}));

import TaskDetailContent from "@/components/task/TaskDetailContent.vue";

describe("task dependency detail view", () => {
  it("shows upstream blocking state and downstream status", () => {
    workspace.findTask.mockReturnValue(task);
    workspace.tasks = [upstream, task, downstream];
    workspace.upstreamTasks.mockReturnValue([upstream]);
    workspace.downstreamTasks.mockReturnValue([downstream]);
    workspace.dependencyState.mockReturnValue({
      blocked: true,
      upstreamCount: 1,
      incompleteUpstreamCount: 1,
      effectiveStartAt: null,
    });

    const wrapper = mount(TaskDetailContent, {
      props: { projectId: "project-1", taskId: "task-c" },
      global: {
        stubs: {
          "van-button": { template: "<button><slot /></button>" },
          "van-field": { template: "<div />" },
          TaskCollaborators: { template: "<div />" },
        },
      },
    });

    const text = wrapper.text();
    expect(text).toContain("上下游");
    expect(text).toContain(
      "当前有 1 个上游任务尚未完成，但不妨碍你提前提交成果",
    );
    expect(text).toContain("Alpha · 进行中");
    expect(text).toContain("等待上游");
    expect(text).toContain("Delta · 待开始");
  });

  it("permits submission while an upstream dependency is incomplete", async () => {
    workspace.currentUserId = "user-1";
    workspace.findTask.mockReturnValue(task);
    workspace.tasks = [upstream, task, downstream];
    workspace.upstreamTasks.mockReturnValue([upstream]);
    workspace.downstreamTasks.mockReturnValue([downstream]);
    workspace.dependencyState.mockReturnValue({
      blocked: true,
      upstreamCount: 1,
      incompleteUpstreamCount: 1,
      effectiveStartAt: null,
    });
    Object.assign(workspace.taskFiles, {
      "task-c": [
        {
          fileId: "file-1",
          logicalName: "work.pdf",
          currentVersionId: "version-1",
          version: 1,
          createdAt: "2026-09-30T00:00:00Z",
          updatedAt: "2026-09-30T00:00:00Z",
          versions: [
            {
              fileVersionId: "version-1",
              versionNumber: 1,
              objectPath: "files/work.pdf",
              originalName: "work.pdf",
              mimeType: "application/pdf",
              sizeBytes: 100,
              sha256Hex: "a".repeat(64),
              createdAt: "2026-09-30T00:00:00Z",
            },
          ],
        },
      ],
    });

    const wrapper = mount(TaskDetailContent, {
      props: { projectId: "project-1", taskId: "task-c" },
      global: {
        stubs: {
          "van-button": {
            props: ["disabled"],
            template: "<button :disabled='disabled'><slot /></button>",
          },
          "van-field": { template: "<div />" },
          TaskCollaborators: { template: "<div />" },
        },
      },
    });

    expect(wrapper.text()).toContain("上游任务尚未完成，你仍可以先提交成果。");
    await wrapper
      .find("textarea[placeholder='可填写本次完成内容……']")
      .setValue("独立完成的下游成果");
    const submit = wrapper
      .findAll("button")
      .find((button) => button.text().includes("提交验收"));
    expect(submit?.attributes("disabled")).toBeUndefined();
  });
});
