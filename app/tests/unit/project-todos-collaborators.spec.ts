import { mount } from "@vue/test-utils";
import { computed } from "vue";
import { describe, expect, it, vi } from "vitest";

import type { TaskRow } from "@/types/ui";

function task(id: string, title: string, assigneeId: string): TaskRow {
  return {
    id,
    project_id: "project-1",
    title,
    description: null,
    deadline_at: "2099-10-10T00:00:00Z",
    weight: 2,
    assignment_state: "assigned",
    status: "in_progress",
    assignee_id: assigneeId,
    accepted_at: "2026-10-01T00:00:00Z",
    completed_at: null,
    progress_text: "",
    blocked_reason: null,
    created_by: "creator-1",
    created_at: "2026-10-01T00:00:00Z",
    updated_at: "2026-10-01T00:00:00Z",
    version: 1,
  } as TaskRow;
}

const primary = task("task-primary", "主负责工作", "current-1");
const collaboration = task("task-collab", "协作工作", "primary-2");
const invitation = task("task-invite", "待接受协作", "primary-3");

const workspace = vi.hoisted(() => ({
  capabilities: {
    canReviewJoinRequest: false,
    canConfirmContributionReport: false,
  },
  joinRequests: [],
  contributionReport: null,
  contributionConfirmations: [],
  currentUserId: "current-1",
  tasks: [] as TaskRow[],
  reviews: [],
  role: "member",
  loading: false,
  error: null,
  project: { id: "project-1" },
  membership: { id: "membership-1" },
  findCollaborator: vi.fn(),
  isAcceptedCollaborator: vi.fn(),
  findOffer: vi.fn().mockReturnValue(null),
  taskResponsibilityKind: vi.fn(),
  loadReviews: vi.fn().mockResolvedValue(undefined),
  loadInvitations: vi.fn().mockResolvedValue(undefined),
  loadContributionReport: vi.fn().mockResolvedValue(undefined),
}));

const navigation = vi.hoisted(() => ({
  rememberSource: vi.fn(),
  openDrawer: vi.fn(),
}));

vi.mock("@/composables/useWorkspaceRoute", () => ({
  useWorkspaceRoute: () => ({
    workspace,
    projectId: computed(() => "project-1"),
    reload: vi.fn(),
  }),
}));
vi.mock("@/stores/task-navigation", () => ({
  useTaskNavigationStore: () => navigation,
}));
vi.mock("@/components/common/PageState.vue", () => ({
  default: { template: "<div><slot /></div>" },
}));
vi.mock("@/components/common/StatusBadge.vue", () => ({
  default: { props: ["status"], template: "<span>{{ status }}</span>" },
}));

import ProjectTodosView from "@/views/ProjectTodosView.vue";

describe("ProjectTodosView collaborator responsibilities", () => {
  it("shows primary work, accepted collaboration, and pending collaboration distinctly", () => {
    workspace.tasks = [primary, collaboration, invitation];
    workspace.findCollaborator.mockImplementation((taskId: string) => {
      if (taskId === "task-collab") {
        return {
          task_id: taskId,
          user_id: "current-1",
          state: "accepted",
        };
      }
      if (taskId === "task-invite") {
        return {
          task_id: taskId,
          user_id: "current-1",
          state: "pending",
        };
      }
      return null;
    });
    workspace.isAcceptedCollaborator.mockImplementation(
      (taskId: string) => taskId === "task-collab",
    );
    workspace.taskResponsibilityKind.mockImplementation((item: TaskRow) => {
      if (item.id === "task-primary") return "primary";
      if (item.id === "task-collab") return "collaborator";
      return null;
    });

    const wrapper = mount(ProjectTodosView, {
      global: {
        stubs: { RouterLink: { template: "<a><slot /></a>" } },
      },
    });

    expect(wrapper.text()).toContain("需要响应");
    expect(wrapper.text()).toContain("进行中");
    expect(wrapper.text()).toContain("主负责工作");
    expect(wrapper.text()).toContain("协作工作");
    expect(wrapper.text()).toContain("待接受协作");
    expect(wrapper.text()).toContain("主负责");
    expect(wrapper.text()).toContain("协作");
    expect(wrapper.text()).toContain("协作邀请");
  });
});
