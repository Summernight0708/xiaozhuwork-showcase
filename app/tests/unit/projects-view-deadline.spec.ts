import { mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  items: [] as unknown[],
  load: vi.fn(),
  loading: false,
  error: null as string | null,
}));

vi.mock("@/stores/projects", () => ({
  useProjectsStore: () => mocks,
}));

import ProjectsView from "@/views/ProjectsView.vue";

const global = {
  stubs: {
    RouterLink: {
      props: ["to"],
      template: '<div class="router-link"><slot /></div>',
    },
    VanButton: { template: "<button><slot /></button>" },
    VanSearch: {
      props: ["modelValue", "placeholder"],
      template: "<input />",
    },
    PageState: { template: "<div><slot /></div>" },
  },
};

function projectItem(options: {
  role?: "leader" | "member";
  myOpenTaskCount?: number;
  lifecycleState?: string;
}) {
  return {
    project: {
      id: "project-1",
      name: "课程项目",
      course_name: "课程",
      deadline_at: "2020-01-01T00:00:00.000Z",
      archived_at: null,
      lifecycle_state: options.lifecycleState ?? "active",
    },
    membership: { id: "membership-1" },
    role: options.role ?? "member",
    capabilities: {},
    myOpenTaskCount: options.myOpenTaskCount ?? 0,
    taskCounts: {
      pending: 0,
      inProgress: 0,
      blocked: 0,
      pendingReview: 0,
      completed: 1,
    },
  };
}

describe("ProjectsView deadline presentation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.items = [];
  });

  it("uses a neutral ended label for an overdue participant with no personal open work", () => {
    mocks.items = [projectItem({ role: "member", myOpenTaskCount: 0 })];
    const wrapper = mount(ProjectsView, { global });

    expect(wrapper.text()).toContain("项目 DDL 已结束");
    expect(wrapper.text()).not.toContain("已超过项目 DDL");
    expect(wrapper.find(".deadline").classes()).not.toContain("overdue");
  });

  it("keeps overdue emphasis when the participant still owns open work", () => {
    mocks.items = [projectItem({ role: "member", myOpenTaskCount: 1 })];
    const wrapper = mount(ProjectsView, { global });

    expect(wrapper.text()).toContain("已超过项目 DDL");
    expect(wrapper.find(".deadline").classes()).toContain("overdue");
  });

  it("keeps overdue emphasis for the leader until the project is closed", () => {
    mocks.items = [projectItem({ role: "leader", myOpenTaskCount: 0 })];
    const wrapper = mount(ProjectsView, { global });

    expect(wrapper.text()).toContain("已超过项目 DDL");
    expect(wrapper.find(".deadline").classes()).toContain("overdue");
  });

  it("shows the completed lifecycle instead of overdue risk", () => {
    mocks.items = [
      projectItem({
        role: "member",
        myOpenTaskCount: 0,
        lifecycleState: "completed",
      }),
    ];
    const wrapper = mount(ProjectsView, { global });

    expect(wrapper.text()).toContain("已完成");
    expect(wrapper.text()).not.toContain("已超过项目 DDL");
  });
});
