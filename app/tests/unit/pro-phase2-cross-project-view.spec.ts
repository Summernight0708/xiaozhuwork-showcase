import { mount, flushPromises } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import CrossProjectOverviewView from "@/views/CrossProjectOverviewView.vue";
import CrossProjectStatistics from "@/components/cross-project/CrossProjectStatistics.vue";
import CrossProjectTrend from "@/components/cross-project/CrossProjectTrend.vue";
import {
  CrossProjectError,
  loadCrossProjectAnalytics,
  searchCrossProjects,
} from "@/services/cross-project";

vi.mock("@/services/cross-project", async (importActual) => {
  const real = await importActual<typeof import("@/services/cross-project")>();
  return {
    ...real,
    searchCrossProjects: vi.fn(),
    loadCrossProjectAnalytics: vi.fn(),
  };
});

const a = "10000000-0000-4000-8000-000000000001";
const b = "10000000-0000-4000-8000-000000000002";
const project = (id: string, name: string) => ({
  projectId: id,
  name,
  courseName: "数据库",
  timezone: "Asia/Shanghai",
  deadlineAt: "2026-12-01T00:00:00Z",
  lifecycleState: "active" as const,
});
const stub = { RouterLink: { template: "<a><slot /></a>" } };
const analytics = {
  ok: true as const,
  schemaVersion: 1 as const,
  scope: "account" as const,
  asOf: "2026-10-01T00:00:00Z",
  provenance: "current_rows" as const,
  historyComplete: false as const,
  window: {
    from: "2026-09-01T00:00:00Z",
    to: "2026-10-01T00:00:00Z",
    bucket: "day" as const,
    timezone: "UTC" as const,
  },
  projectCount: 1,
  completionRate: 0.5,
  totals: {
    taskTotal: 4,
    completedTasks: 2,
    overdueTasks: 1,
    blockedTasks: 1,
    awaitingReviewTasks: 1,
    completedInWindow: 1,
  },
  difficultyDistribution: [1, 2, 3, 4, 5, null].map((stars, i) => ({
    stars,
    count: i === 5 ? 4 : 0,
  })),
  trends: [{ day: "2026-09-30", created: 2, completed: 1 }],
  projects: [
    {
      projectId: a,
      taskTotal: 4,
      completedTasks: 2,
      overdueTasks: 1,
      blockedTasks: 1,
      awaitingReviewTasks: 1,
    },
  ],
};

beforeEach(() => {
  vi.resetAllMocks();
  vi.mocked(searchCrossProjects).mockResolvedValue({
    ok: true,
    schemaVersion: 1,
    projects: [project(a, "算法作业")],
    nextCursor: null,
  });
  vi.mocked(loadCrossProjectAnalytics).mockResolvedValue(analytics);
});

describe("F standalone workspace", () => {
  it("shows owned project list and localizes course + status", async () => {
    const wrapper = mount(CrossProjectOverviewView, {
      global: { stubs: stub },
    });
    await flushPromises();
    expect(wrapper.text()).toContain("算法作业");
    expect(wrapper.text()).toContain("数据库");
    expect(wrapper.text()).toContain("进行中");
    expect(searchCrossProjects).toHaveBeenCalledWith("", null);
  });
  it("server-searches and paginates with cursor", async () => {
    vi.mocked(searchCrossProjects)
      .mockResolvedValueOnce({
        ok: true,
        schemaVersion: 1,
        projects: [project(a, "算法作业")],
        nextCursor: a,
      })
      .mockResolvedValueOnce({
        ok: true,
        schemaVersion: 1,
        projects: [project(b, "课程设计")],
        nextCursor: null,
      })
      .mockResolvedValueOnce({
        ok: true,
        schemaVersion: 1,
        projects: [project(b, "课程设计")],
        nextCursor: null,
      });
    const wrapper = mount(CrossProjectOverviewView, {
      global: { stubs: stub },
    });
    await flushPromises();
    await wrapper.find(".project-list button").trigger("click");
    await flushPromises();
    expect(searchCrossProjects).toHaveBeenCalledWith("", a);
    expect(wrapper.text()).toContain("课程设计");
    await wrapper.find('input[type="search"]').setValue("  数据库 ");
    await wrapper.find("form").trigger("submit");
    await flushPromises();
    expect(searchCrossProjects).toHaveBeenCalledWith("数据库", null);
  });
  it("distinguishes unpublished and Free/expired account states", async () => {
    vi.mocked(searchCrossProjects).mockRejectedValueOnce(
      new CrossProjectError("CAPABILITY_NOT_AVAILABLE"),
    );
    const unreleased = mount(CrossProjectOverviewView, {
      global: { stubs: stub },
    });
    await flushPromises();
    expect(unreleased.text()).toContain("尚未正式发布");
    vi.mocked(searchCrossProjects).mockRejectedValueOnce(
      new CrossProjectError("CAPABILITY_REQUIRES_PRO"),
    );
    const free = mount(CrossProjectOverviewView, { global: { stubs: stub } });
    await flushPromises();
    expect(free.text()).toContain("有效 Account Pro");
  });
  it("renders aggregates, UTC trend and historical incompleteness caveat", async () => {
    const wrapper = mount(CrossProjectOverviewView, {
      global: { stubs: stub },
    });
    await flushPromises();
    await wrapper.find(".filter-row button").trigger("click");
    await flushPromises();
    expect(loadCrossProjectAnalytics).toHaveBeenCalledOnce();
    expect(wrapper.text()).toContain("历史数据不完整");
    expect(wrapper.text()).toContain("每日创建与完成趋势");
    expect(wrapper.text()).toContain("50.0%");
  });
  it("handles analytics unavailable without pretending success", async () => {
    vi.mocked(loadCrossProjectAnalytics).mockRejectedValueOnce(
      new CrossProjectError("SERVICE_UNAVAILABLE"),
    );
    const wrapper = mount(CrossProjectOverviewView, {
      global: { stubs: stub },
    });
    await flushPromises();
    await wrapper.find(".filter-row button").trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("统计服务尚未就绪");
    expect(wrapper.findComponent(CrossProjectStatistics).exists()).toBe(false);
    expect(wrapper.findComponent(CrossProjectTrend).exists()).toBe(false);
  });
});
