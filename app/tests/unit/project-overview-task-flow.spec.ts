import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => {
  const tasks = [
    {
      id: "task-a",
      project_id: "project-1",
      title: "资料收集",
      status: "completed",
      assignee_id: "user-1",
      assignment_state: "assigned",
      deadline_at: "2026-10-01T00:00:00.000Z",
      weight: 1,
    },
    {
      id: "task-b",
      project_id: "project-1",
      title: "答辩 PPT",
      status: "in_progress",
      assignee_id: "user-2",
      assignment_state: "assigned",
      deadline_at: "2099-10-10T00:00:00.000Z",
      weight: 2,
    },
  ];
  const navigation = {
    source: {
      routeName: "project-overview",
      projectId: "project-1",
      taskId: "task-b",
      scrollY: 320,
      state: {
        graphZoom: 70,
        graphPanX: -120,
        graphPanY: 30,
        graphScope: "all",
        graphSearch: "答辩",
        graphFocusTaskId: "task-b",
        graphHistoryExpanded: true,
      },
    },
    rememberSource: vi.fn(),
    openDrawer: vi.fn(),
  };
  return {
    projectId: { __v_isRef: true, value: "project-1" },
    reload: vi.fn(),
    navigation,
    notifications: {
      items: [
        {
          id: "notice-1",
          project_id: "project-1",
          title: "任务有更新",
          message: "答辩 PPT 已提交新版本",
          read_at: null,
          created_at: "2026-10-04T01:00:00.000Z",
        },
      ],
    },
    workspace: {
      loading: false,
      error: null,
      project: {
        id: "project-1",
        name: "数据库课程设计",
        course_name: "数据库系统",
        deadline_at: "2099-12-20T12:00:00.000Z",
        archived_at: null,
      },
      membership: { id: "membership-1" },
      members: [
        {
          id: "member-1",
          user_id: "user-1",
          display_name_snapshot: "张三",
        },
        {
          id: "member-2",
          user_id: "user-2",
          display_name_snapshot: "李四",
        },
      ],
      tasks,
      taskDependencies: [
        {
          upstream_task_id: "task-a",
          downstream_task_id: "task-b",
        },
      ],
      currentUserId: "user-1",
      capabilities: { canManageInvites: true, canCreateTask: true },
      dependencyState: vi.fn(() => ({ blocked: false })),
      taskDisplayStatus: vi.fn((task: { status: string }) => task.status),
      memberName: vi.fn((id: string) => (id === "user-1" ? "张三" : "李四")),
      findTask: vi.fn(
        (id: string) => tasks.find((task) => task.id === id) ?? null,
      ),
    },
  };
});

vi.mock("@/stores/auth", () => ({
  useAuthStore: () => ({ user: { id: "user-1" } }),
}));
vi.mock("@/stores/help", () => ({
  useHelpStore: () => ({
    loadedForUserId: null,
    dismissed: new Set(),
    syncError: false,
    loadForUser: vi.fn(),
    dismiss: vi.fn(),
    reset: vi.fn(),
  }),
}));

vi.mock("@/composables/useWorkspaceRoute", () => ({
  useWorkspaceRoute: () => ({
    workspace: mocks.workspace,
    projectId: mocks.projectId,
    reload: mocks.reload,
  }),
}));
vi.mock("@/stores/task-navigation", () => ({
  useTaskNavigationStore: () => mocks.navigation,
}));
vi.mock("@/stores/notifications", () => ({
  useNotificationsStore: () => mocks.notifications,
}));

import TaskFlowGraph from "@/components/TaskFlowGraph.vue";
import ProjectOverviewView from "@/views/ProjectOverviewView.vue";

const global = {
  stubs: {
    RouterLink: {
      props: ["to"],
      template: '<a href="#"><slot /></a>',
    },
    VanButton: {
      template: "<button><slot /></button>",
    },
    VanLoading: {
      template: "<span>loading</span>",
    },
    VanEmpty: {
      template: "<div><slot /></div>",
    },
  },
};

describe("ProjectOverview TaskFlowGraph integration", () => {
  it("uses the graph as the primary view with action-oriented rail summaries", () => {
    const wrapper = mount(ProjectOverviewView, { global });

    expect(wrapper.get("h1").text()).toBe("数据库课程设计");
    expect(wrapper.get(".graph-column").text()).toContain("任务工作流");
    expect(wrapper.findComponent(TaskFlowGraph).exists()).toBe(true);
    expect(wrapper.get(".attention-card").text()).toContain("等待上游");
    expect(wrapper.get(".attention-card").text()).toContain("阻塞");
    expect(wrapper.get(".attention-card").text()).toContain("逾期");
    expect(wrapper.get(".attention-card").text()).toContain("待验收");
    expect(wrapper.get(".attention-card").text()).toContain("待接受");
    expect(wrapper.text()).toContain("成员工作摘要");
    expect(wrapper.text()).toContain("主负责 1");
    expect(wrapper.text()).toContain("最近通知");
    expect(wrapper.text()).toContain("答辩 PPT 已提交新版本");
  });

  it("restores graph state from the existing task-navigation source snapshot", () => {
    const wrapper = mount(ProjectOverviewView, { global });
    const graph = wrapper.findComponent(TaskFlowGraph);

    expect(graph.props("initialState")).toMatchObject({
      zoom: 70,
      panX: -120,
      panY: 30,
      scope: "all",
      search: "答辩",
      focusTaskId: "task-b",
      historyExpanded: true,
    });
  });

  it("saves graph state and opens the existing task drawer architecture", async () => {
    vi.clearAllMocks();
    const wrapper = mount(ProjectOverviewView, { global });
    const graph = wrapper.findComponent(TaskFlowGraph);

    graph.vm.$emit("state-change", {
      zoom: 82,
      panX: -50,
      panY: 24,
      scope: "workflow",
      search: "",
      focusTaskId: "task-b",
      historyExpanded: false,
    });
    graph.vm.$emit("open-task", "task-b");
    await flushPromises();

    expect(mocks.navigation.rememberSource).toHaveBeenCalledWith(
      expect.objectContaining({
        routeName: "project-overview",
        projectId: "project-1",
        taskId: "task-b",
        state: expect.objectContaining({
          graphZoom: 82,
          graphPanX: -50,
          graphPanY: 24,
          graphScope: "workflow",
          graphFocusTaskId: "task-b",
        }),
      }),
    );
    expect(mocks.navigation.openDrawer).toHaveBeenCalledWith(
      "project-1",
      "task-b",
    );
  });

  it("switches mobile overview to action-first content and lazy mounts the graph", async () => {
    const media = {
      matches: true,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    };
    vi.stubGlobal(
      "matchMedia",
      vi.fn(() => media),
    );

    const wrapper = mount(ProjectOverviewView, { global });
    await flushPromises();

    expect(wrapper.text()).toContain("我的待办");
    expect(wrapper.text()).toContain("任务流程");
    expect(wrapper.text()).toContain("成员工作");
    expect(wrapper.find(".head-actions").exists()).toBe(false);
    expect(wrapper.find(".attention-card").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("最近通知");
    expect(wrapper.findComponent(TaskFlowGraph).exists()).toBe(false);

    await wrapper.get(".mobile-overview__toggle").trigger("click");
    await flushPromises();
    expect(wrapper.findComponent(TaskFlowGraph).exists()).toBe(true);

    wrapper.unmount();
    vi.unstubAllGlobals();
  });

  it("keeps Files/Reviews/etc out of the overview replacement responsibility", () => {
    const wrapper = mount(ProjectOverviewView, { global });
    expect(wrapper.text()).not.toContain("任务关系 / 成员工作");
    expect(wrapper.text()).not.toContain("完整通知中心");
  });
});
