import type {
  ProductAnalyticsOverviewV1,
  ProductAnalyticsSeriesPointV1,
  ProductAnalyticsLifecycleDimensionV1,
  ProductAnalyticsMetricKeyV1,
  RateFact,
} from "@ops/features/analytics/contracts";
import { callOpsApi } from "@ops/lib/ops-api";

const METRICS = new Set<ProductAnalyticsMetricKeyV1>([
  "wacp",
  "project_activation_numerator",
  "project_activation_denominator",
  "user_activation_numerator",
  "user_activation_denominator",
  "first_value_numerator",
  "first_value_denominator",
  "core_loop_completed",
  "project_completion_numerator",
  "project_completion_denominator",
  "lifecycle_project_count",
]);

const LIFECYCLE = new Set<ProductAnalyticsLifecycleDimensionV1>([
  "setup",
  "collaborating",
  "quiet",
  "stalled",
  "completed",
  "archived",
]);

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function nonNegative(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function rateFact(value: unknown): RateFact | null {
  const data = record(value);
  if (
    !data ||
    !nonNegative(data.numerator) ||
    !nonNegative(data.denominator) ||
    !(
      data.rate === null ||
      (typeof data.rate === "number" &&
        Number.isFinite(data.rate) &&
        data.rate >= 0 &&
        data.rate <= 1)
    )
  ) {
    return null;
  }
  return {
    numerator: data.numerator,
    denominator: data.denominator,
    rate: data.rate as number | null,
  };
}

export function sanitizeProductOverview(
  value: unknown,
): ProductAnalyticsOverviewV1 | null {
  const data = record(value);
  const coverage = record(data?.coverage);
  const wacp = record(data?.wacp);
  const lifecycle = record(data?.lifecycle);
  const projectActivation = rateFact(data?.projectActivation);
  const userActivation = rateFact(data?.userActivation);
  const firstValueRate = rateFact(data?.firstValueRate);
  const projectCompletion = rateFact(data?.projectCompletion);

  if (
    !data ||
    data.schemaVersion !== 1 ||
    data.definitionVersion !== 1 ||
    !coverage ||
    !(
      coverage.businessAnalyticsCompleteSince === null ||
      typeof coverage.businessAnalyticsCompleteSince === "string"
    ) ||
    typeof coverage.partial !== "boolean" ||
    !wacp ||
    typeof wacp.weekStart !== "string" ||
    !nonNegative(wacp.value) ||
    !projectActivation ||
    !userActivation ||
    !firstValueRate ||
    !projectCompletion ||
    !nonNegative(data.coreLoopCompleted) ||
    !lifecycle ||
    !nonNegative(lifecycle.setup) ||
    !nonNegative(lifecycle.collaborating) ||
    !nonNegative(lifecycle.quiet) ||
    !nonNegative(lifecycle.stalled) ||
    !nonNegative(lifecycle.completed) ||
    !nonNegative(lifecycle.archived)
  ) {
    return null;
  }

  return {
    schemaVersion: 1,
    definitionVersion: 1,
    coverage: {
      businessAnalyticsCompleteSince:
        coverage.businessAnalyticsCompleteSince as string | null,
      partial: coverage.partial,
    },
    wacp: { weekStart: wacp.weekStart, value: wacp.value },
    projectActivation,
    userActivation,
    firstValueRate,
    coreLoopCompleted: data.coreLoopCompleted,
    lifecycle: {
      setup: lifecycle.setup,
      collaborating: lifecycle.collaborating,
      quiet: lifecycle.quiet,
      stalled: lifecycle.stalled,
      completed: lifecycle.completed,
      archived: lifecycle.archived,
    },
    projectCompletion,
  };
}

export function sanitizeProductSeries(
  value: unknown,
): ProductAnalyticsSeriesPointV1[] | null {
  if (!Array.isArray(value)) return null;
  const result: ProductAnalyticsSeriesPointV1[] = [];

  for (const item of value) {
    const data = record(item);
    if (
      !data ||
      typeof data.date !== "string" ||
      typeof data.metricKey !== "string" ||
      !METRICS.has(data.metricKey as ProductAnalyticsMetricKeyV1) ||
      typeof data.dimensionKey !== "string" ||
      !(
        data.dimensionKey === "" ||
        LIFECYCLE.has(data.dimensionKey as ProductAnalyticsLifecycleDimensionV1)
      ) ||
      !nonNegative(data.value) ||
      !nonNegative(data.sampleSize)
    ) {
      return null;
    }
    result.push({
      date: data.date,
      metricKey: data.metricKey as ProductAnalyticsMetricKeyV1,
      dimensionKey: data.dimensionKey as
        "" | ProductAnalyticsLifecycleDimensionV1,
      value: data.value,
      sampleSize: data.sampleSize,
    });
  }

  return result;
}

function shiftIsoDate(date: string, days: number): string {
  const value = new Date(date + "T00:00:00.000Z");
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

function shanghaiDate(now: Date): string {
  return new Date(now.getTime() + 8 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
}

export function recentAnalyticsWindow(now = new Date()) {
  const to = new Date(now);
  const from = new Date(now);
  from.setUTCDate(from.getUTCDate() - 28);

  const lastCompleteDate = shiftIsoDate(shanghaiDate(now), -1);
  return {
    from: from.toISOString(),
    to: to.toISOString(),
    fromDate: shiftIsoDate(lastCompleteDate, -27),
    toDate: lastCompleteDate,
  };
}
export async function loadProductOverview(
  accessToken: string,
  now = new Date(),
): Promise<ProductAnalyticsOverviewV1 | null> {
  const window = recentAnalyticsWindow(now);
  const response = await callOpsApi<ProductAnalyticsOverviewV1>(
    {
      action: "analytics.overview",
      from: window.from,
      to: window.to,
      definitionVersion: 1,
    },
    accessToken,
  );
  return response.ok ? sanitizeProductOverview(response.data) : null;
}

export async function loadProductTimeseries(
  accessToken: string,
  now = new Date(),
): Promise<ProductAnalyticsSeriesPointV1[] | null> {
  const window = recentAnalyticsWindow(now);
  const response = await callOpsApi<ProductAnalyticsSeriesPointV1[]>(
    {
      action: "analytics.timeseries",
      fromDate: window.fromDate,
      toDate: window.toDate,
      definitionVersion: 1,
    },
    accessToken,
  );
  return response.ok ? sanitizeProductSeries(response.data) : null;
}
