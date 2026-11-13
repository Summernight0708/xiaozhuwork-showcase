import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";

import AnalyticsSummaryCards from "@/components/analytics/AnalyticsSummaryCards.vue";
import AnalyticsTrendsChart from "@/components/analytics/AnalyticsTrendsChart.vue";
import AnalyticsDistributionPanels from "@/components/analytics/AnalyticsDistributionPanels.vue";
import AnalyticsTimingCycle from "@/components/analytics/AnalyticsTimingCycle.vue";
import AnalyticsProvenanceNotice from "@/components/analytics/AnalyticsProvenanceNotice.vue";
import {
  ProjectAnalyticsServiceError,
  createDefaultAnalyticsWindow,
  createProjectAnalyticsService,
  parseProjectAnalyticsResponse,
  projectAnalyticsFailurePresentation,
  validateProjectAnalyticsRequest,
  type ProjectAnalytics,
} from "@/services/project-analytics";

const projectId = "c2000000-0000-4000-8000-000000000001";

const analytics: ProjectAnalytics = {
  ok: true,
  schemaVersion: 1,
  projectId,
  asOf: "2026-10-06T12:00:00.000000Z",
  provenance: "current_rows",
  historyComplete: false,
  projectTimezone: "Asia/Shanghai",
  window: {
    from: "2026-10-01T00:00:00.000000Z",
    to: "2026-10-06T00:00:00.000000Z",
    bucket: "day",
    timezone: "UTC",
  },
  totals: {
    taskTotal: 6,
    completedTasks: 2,
    overdueTasks: 1,
    awaitingReviewTasks: 1,
    blockedTasks: 2,
    completedInWindow: 2,
  },
  memberTaskDistribution: [
    { kind: "active_member", userId: "user-1", count: 3 },
    { kind: "former_member", userId: null, count: 2 },
    { kind: "unassigned", userId: null, count: 1 },
  ],
  difficultyDistribution: [
    { stars: 1, count: 1 },
    { stars: 2, count: 1 },
    { stars: 3, count: 1 },
    { stars: 4, count: 1 },
    { stars: 5, count: 1 },
    { stars: null, count: 1 },
  ],
  completionTiming: {
    count: 2,
    averageSeconds: 5400,
    medianSeconds: 5400,
    invalidTimeRows: 0,
  },
  projectCycle: {
    startAt: "2026-09-01T00:00:00.000000Z",
    startSource: "start_at",
    deadlineAt: "2026-11-01T00:00:00.000000Z",
    completedAt: null,
    completedCycleSeconds: null,
    elapsedSeconds: 3070800,
  },
  trends: [
    { day: "2026-10-01", created: 1, completed: 0 },
    { day: "2026-10-02", created: 0, completed: 1 },
  ],
  dataIssues: {
    completedMissingTime: 0,
    historicalStatusReconstructionAvailable: false,
    collaboratorCreditAvailable: false,
  },
};

describe("project analytics client contract", () => {
  it("builds the default half-open 30-day UTC request window", () => {
    expect(
      createDefaultAnalyticsWindow(new Date("2026-10-06T12:34:56.789Z")),
    ).toEqual({
      from: "2026-09-06T12:34:56.789Z",
      to: "2026-10-06T12:34:56.789Z",
    });
  });

  it("validates UUIDs, half-open ordering, and the 180-day maximum", () => {
    expect(() =>
      validateProjectAnalyticsRequest({
        projectId,
        from: "2026-01-01T00:00:00.000Z",
        to: "2026-06-30T00:00:00.000Z",
      }),
    ).not.toThrow();
    expect(() =>
      validateProjectAnalyticsRequest({
        projectId,
        from: "2026-01-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.001Z",
      }),
    ).toThrow(/180/);
    expect(() =>
      validateProjectAnalyticsRequest({
        projectId: "not-a-uuid",
        from: "2026-01-01T00:00:00.000Z",
        to: "2026-01-02T00:00:00.000Z",
      }),
    ).toThrow(/project/i);
    expect(() =>
      validateProjectAnalyticsRequest({
        projectId,
        from: "not-a-timestamp",
        to: "2026-01-02T00:00:00.000Z",
      }),
    ).toThrow(/ISO/);
  });

  it("calls the isolated RPC adapter and accepts the exact schema v1 payload", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: analytics, error: null });
    const service = createProjectAnalyticsService({ rpc });

    await expect(
      service.getProjectAnalytics({
        projectId,
        from: analytics.window.from,
        to: analytics.window.to,
      }),
    ).resolves.toEqual(analytics);
    expect(rpc).toHaveBeenCalledWith("get_project_analytics", {
      p_project_id: projectId,
      p_from: analytics.window.from,
      p_to: analytics.window.to,
    });
  });

  it("preserves safe domain failures and rejects malformed success payloads", async () => {
    const denied = createProjectAnalyticsService({
      rpc: vi.fn().mockResolvedValue({
        data: { ok: false, code: "CAPABILITY_REQUIRES_PRO" },
        error: null,
      }),
    });
    await expect(
      denied.getProjectAnalytics({
        projectId,
        from: analytics.window.from,
        to: analytics.window.to,
      }),
    ).resolves.toEqual({ ok: false, code: "CAPABILITY_REQUIRES_PRO" });

    expect(() =>
      parseProjectAnalyticsResponse({
        ...analytics,
        difficultyDistribution: analytics.difficultyDistribution.slice(0, 5),
      }),
    ).toThrow(ProjectAnalyticsServiceError);
    expect(() =>
      parseProjectAnalyticsResponse({
        ...analytics,
        totals: { ...analytics.totals, taskTotal: Number.MAX_SAFE_INTEGER + 1 },
      }),
    ).toThrow(ProjectAnalyticsServiceError);
  });

  it("renders the six authoritative current-state totals", () => {
    const wrapper = mount(AnalyticsSummaryCards, {
      props: { totals: analytics.totals },
    });

    expect(
      wrapper.findAll("[data-test='analytics-summary-card']"),
    ).toHaveLength(6);
    expect(wrapper.text()).toContain("任务总数");
    expect(wrapper.text()).toContain("窗口内完成");
    expect(wrapper.text()).toContain("6");
  });

  it("renders trends, distributions, timing, and current-row provenance", () => {
    const trends = mount(AnalyticsTrendsChart, {
      props: { trends: analytics.trends },
    });
    expect(trends.find("svg").exists()).toBe(true);
    expect(trends.text()).toContain("UTC");

    const distributions = mount(AnalyticsDistributionPanels, {
      props: {
        members: analytics.memberTaskDistribution,
        difficulty: analytics.difficultyDistribution,
      },
    });
    expect(distributions.text()).toContain("已离开成员");
    expect(distributions.text()).toContain("未评级");

    const timing = mount(AnalyticsTimingCycle, {
      props: {
        timing: analytics.completionTiming,
        cycle: analytics.projectCycle,
      },
    });
    expect(timing.text()).toContain("1 小时 30 分钟");
    expect(timing.text()).toContain("项目周期");

    const provenance = mount(AnalyticsProvenanceNotice, {
      props: { analytics },
    });
    expect(provenance.text()).toContain("当前保留任务行");
    expect(provenance.text()).toContain("不包含协作者贡献推断");
  });

  it("uses distinct unreleased, Free, and denied access messages", () => {
    expect(
      projectAnalyticsFailurePresentation("CAPABILITY_NOT_AVAILABLE").title,
    ).toContain("尚未发布");
    expect(
      projectAnalyticsFailurePresentation("CAPABILITY_REQUIRES_PRO").title,
    ).toContain("Pro");
    expect(
      projectAnalyticsFailurePresentation("NOT_FOUND_OR_NOT_AUTHORIZED").title,
    ).toContain("无法访问");
  });
});
