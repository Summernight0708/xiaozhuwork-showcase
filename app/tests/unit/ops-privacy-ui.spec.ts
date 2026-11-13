import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import PrivacyMetric from "@ops/components/PrivacyMetric.vue";
import type {
  ProductAnalyticsOverviewV1,
  ProductAnalyticsSeriesPointV1,
  RateFact,
} from "@ops/features/analytics/contracts";
import {
  formatPrivateMetric,
  formatPrivateRate,
} from "@shared/analytics/privacy";

describe("Ops privacy metrics and frozen analytics contract", () => {
  it("suppresses cohort values below k=5", () => {
    expect(formatPrivateMetric(4, 4)).toBe("<5");
    expect(formatPrivateRate(0.5, 4)).toBe("<5");
  });

  it("shows exact aggregate/cohort values at k=5", () => {
    expect(formatPrivateMetric(5, 5)).toBe("5");
    expect(formatPrivateMetric(42, null)).toBe("42");
    expect(formatPrivateRate(0.5, 5)).toBe("50%");
  });

  it("never renders a percentage for a suppressed cell", () => {
    const wrapper = mount(PrivacyMetric, {
      props: {
        label: "Activation",
        value: 4,
        sampleSize: 4,
        rate: 0.5,
      },
    });

    expect(wrapper.text()).toContain("<5");
    expect(wrapper.text()).not.toContain("50%");
    expect(wrapper.attributes("data-suppressed")).toBe("true");
  });

  it("renders rate only when the cohort is not suppressed", () => {
    const wrapper = mount(PrivacyMetric, {
      props: {
        label: "Activation",
        value: 5,
        sampleSize: 5,
        rate: 0.5,
      },
    });

    expect(wrapper.text()).toContain("5");
    expect(wrapper.text()).toContain("50%");
    expect(wrapper.attributes("data-suppressed")).toBe("false");
  });

  it("freezes the v1 analytics DTO names and shapes", () => {
    const rate: RateFact = { numerator: 2, denominator: 4, rate: 0.5 };
    const overview: ProductAnalyticsOverviewV1 = {
      schemaVersion: 1,
      definitionVersion: 1,
      coverage: {
        businessAnalyticsCompleteSince: "2026-10-14T00:00:00.000Z",
        partial: false,
      },
      wacp: { weekStart: "2026-10-12", value: 8 },
      projectActivation: rate,
      userActivation: rate,
      firstValueRate: rate,
      coreLoopCompleted: 6,
      lifecycle: {
        setup: 1,
        collaborating: 2,
        quiet: 3,
        stalled: 4,
        completed: 5,
        archived: 6,
      },
      projectCompletion: rate,
    };
    const point: ProductAnalyticsSeriesPointV1 = {
      date: "2026-10-14",
      metricKey: "lifecycle_project_count",
      dimensionKey: "collaborating",
      value: 5,
      sampleSize: 5,
    };

    expect(overview.schemaVersion).toBe(1);
    expect(point.dimensionKey).toBe("collaborating");
  });
});
