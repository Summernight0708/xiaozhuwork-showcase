export type RateFact = {
  numerator: number;
  denominator: number;
  rate: number | null;
};

export type ProductAnalyticsOverviewV1 = {
  schemaVersion: 1;
  definitionVersion: 1;
  coverage: {
    businessAnalyticsCompleteSince: string | null;
    partial: boolean;
  };
  wacp: {
    weekStart: string;
    value: number;
  };
  projectActivation: RateFact;
  userActivation: RateFact;
  firstValueRate: RateFact;
  coreLoopCompleted: number;
  lifecycle: {
    setup: number;
    collaborating: number;
    quiet: number;
    stalled: number;
    completed: number;
    archived: number;
  };
  projectCompletion: RateFact;
};

export type ProductAnalyticsMetricKeyV1 =
  | "wacp"
  | "project_activation_numerator"
  | "project_activation_denominator"
  | "user_activation_numerator"
  | "user_activation_denominator"
  | "first_value_numerator"
  | "first_value_denominator"
  | "core_loop_completed"
  | "project_completion_numerator"
  | "project_completion_denominator"
  | "lifecycle_project_count";

export type ProductAnalyticsLifecycleDimensionV1 =
  "setup" | "collaborating" | "quiet" | "stalled" | "completed" | "archived";

export type ProductAnalyticsSeriesPointV1 = {
  date: string;
  metricKey: ProductAnalyticsMetricKeyV1;
  dimensionKey: "" | ProductAnalyticsLifecycleDimensionV1;
  value: number;
  sampleSize: number;
};
