/* global process, fetch, console */
import assert from "node:assert/strict";
import postgres from "postgres";

const apiUrl = process.env.SUPABASE_URL;
const roleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbUrl = process.env.SUPABASE_DB_URL;
const metricDate = process.env.ANALYTICS_ROLLUP_TEST_DATE ?? "2099-01-05";

if (
  apiUrl !== "http://127.0.0.1:54321" ||
  !roleKey ||
  !dbUrl?.includes("127.0.0.1:54322/postgres") ||
  !/^\d{4}-\d{2}-\d{2}$/.test(metricDate)
) {
  throw new Error("Analytics rollup test requires local Supabase 54321/54322");
}

const db = postgres(dbUrl, { max: 2, ssl: false });

async function invoke() {
  const response = await fetch(apiUrl + "/functions/v1/analytics-rollup", {
    method: "POST",
    headers: {
      apikey: roleKey,
      authorization: "Bearer " + roleKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      fromDate: metricDate,
      toDate: metricDate,
      definitionVersion: 1,
    }),
  });
  const payload = await response.json().catch(() => ({}));
  assert.equal(response.status, 200, JSON.stringify(payload));
  assert.equal(payload.ok, true, JSON.stringify(payload));
}

try {
  await db`
    delete from private.analytics_daily_metrics
    where metric_date=${metricDate}::date and definition_version=1
  `;

  await invoke();
  await invoke();

  const [summary] = await db`
    select
      count(*)::integer as rows,
      count(distinct (
        metric_date,metric_key,dimension_key,definition_version
      ))::integer as unique_rows
    from private.analytics_daily_metrics
    where metric_date=${metricDate}::date
      and definition_version=1
  `;

  assert.equal(summary.rows, 16);
  assert.equal(summary.unique_rows, 16);

  const [wacp] = await db`
    select numeric_value::integer as value
    from private.analytics_daily_metrics
    where metric_date=${metricDate}::date
      and metric_key='wacp'
      and dimension_key=''
      and definition_version=1
  `;
  assert.ok(wacp);

  console.log("Analytics rollup local HTTP idempotency: PASS");
} finally {
  await db`
    delete from private.analytics_daily_metrics
    where metric_date=${metricDate}::date and definition_version=1
  `.catch(() => undefined);
  await db.end();
}
