import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import ActivationFunnel from "@ops/features/analytics/ActivationFunnel.vue";
import ProductOverview from "@ops/features/analytics/ProductOverview.vue";
import ProjectLifecycleSummary from "@ops/features/analytics/ProjectLifecycleSummary.vue";
import type { ProductAnalyticsOverviewV1 } from "@ops/features/analytics/contracts";

function fixture(
  options: {
    partial?: boolean;
    projectSample?: number;
    userSample?: number;
  } = {},
): ProductAnalyticsOverviewV1 {
  const projectSample = options.projectSample ?? 8;
  const userSample = options.userSample ?? 9;
  return {
    schemaVersion: 1,
    definitionVersion: 1,
    coverage: {
      businessAnalyticsCompleteSince: "2026-10-14T00:00:00+00:00",
      partial: options.partial ?? false,
    },
    wacp: { weekStart: "2026-10-12", value: 12 },
    projectActivation: {
      numerator: Math.min(6, projectSample),
      denominator: projectSample,
      rate:
        projectSample === 0 ? null : Math.min(6, projectSample) / projectSample,
    },
    userActivation: {
      numerator: Math.min(5, userSample),
      denominator: userSample,
      rate: userSample === 0 ? null : Math.min(5, userSample) / userSample,
    },
    firstValueRate: {
      numerator: Math.min(4, projectSample),
      denominator: projectSample,
      rate:
        projectSample === 0 ? null : Math.min(4, projectSample) / projectSample,
    },
    coreLoopCompleted: 17,
    lifecycle: {
      setup: 1,
      collaborating: 3,
      quiet: 1,
      stalled: 1,
      completed: 2,
      archived: 0,
    },
    projectCompletion: {
      numerator: 2,
      denominator: projectSample,
      rate: projectSample === 0 ? null : 2 / projectSample,
    },
  };
}

describe("Ops beta product analytics presentation", () => {
  it("makes WACP the primary metric and keeps diagnostics secondary", () => {
    const wrapper = mount(ProductOverview, {
      props: { overview: fixture() },
    });

    const northStar = wrapper.get('[data-testid="wacp-north-star"]');
    expect(northStar.text()).toContain("WACP");
    expect(northStar.text()).toContain("12");
    expect(wrapper.text()).toContain("项目激活");
    expect(wrapper.text()).toContain("First Value");
    expect(wrapper.text()).toContain("核心闭环完成");
  });

  it("surfaces partial coverage instead of presenting incomplete history as complete", () => {
    const wrapper = mount(ProductOverview, {
      props: { overview: fixture({ partial: true }) },
    });

    expect(wrapper.get('[data-testid="coverage-status"]').text()).toContain(
      "部分覆盖",
    );
    expect(wrapper.text()).toContain("2026-10-14");
  });

  it("suppresses activation cohorts below k=5 and hides their percentages", () => {
    const wrapper = mount(ActivationFunnel, {
      props: {
        overview: fixture({ projectSample: 4, userSample: 4 }),
      },
    });

    expect(wrapper.text()).toContain("<5");
    expect(wrapper.text()).not.toMatch(/\d+(?:\.\d+)?%/);
    expect(
      wrapper.findAll('[data-suppressed="true"]').length,
    ).toBeGreaterThanOrEqual(3);
  });

  it("uses the project cohort size for lifecycle privacy suppression", () => {
    const suppressed = mount(ProjectLifecycleSummary, {
      props: { overview: fixture({ projectSample: 4 }) },
    });
    expect(suppressed.findAll('[data-suppressed="true"]').length).toBe(6);
    expect(suppressed.text()).not.toContain("3");

    const visible = mount(ProjectLifecycleSummary, {
      props: { overview: fixture({ projectSample: 8 }) },
    });
    expect(visible.text()).toContain("协作中");
    expect(visible.text()).toContain("3");
  });
});
