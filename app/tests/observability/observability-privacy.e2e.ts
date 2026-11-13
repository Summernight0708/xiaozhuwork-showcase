import { expect, test } from "@playwright/test";
import postgres from "postgres";

import { localSupabase, registerWithPassword } from "../e2e/local-supabase";

const PROJECT_ID = "123e4567-e89b-12d3-a456-426614174000";
const TASK_ID = "123e4567-e89b-12d3-a456-426614174001";
const FAKE_TITLE = "OBS_FAKE_PROJECT_NAME";
const FAKE_EMAIL = "obs-sensitive@example.edu";
const FAKE_TOKEN = "OBS_FAKE_TOKEN";
const FAKE_OTP = "654321";

test("browser telemetry sends only normalized non-sensitive data", async ({
  page,
}) => {
  const umamiPayloads: Array<Record<string, unknown>> = [];
  const sentryBodies: string[] = [];

  await page.route("https://analytics.test/**", async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname === "/script.js") {
      await route.fulfill({
        status: 200,
        contentType: "application/javascript",
        body: [
          "window.umami={",
          "track:function(payload){",
          "return fetch('https://analytics.test/capture',{",
          "method:'POST',headers:{'content-type':'application/json'},",
          "body:JSON.stringify(payload)",
          "});",
          "}",
          "};",
        ].join(""),
      });
      return;
    }

    if (url.pathname === "/capture") {
      const body = route.request().postData();
      if (body) umamiPayloads.push(JSON.parse(body) as Record<string, unknown>);
      await route.fulfill({ status: 204, body: "" });
      return;
    }

    await route.fulfill({ status: 404, body: "" });
  });

  await page.route("https://example.ingest.sentry.io/**", async (route) => {
    const body = route.request().postData();
    if (body) sentryBodies.push(body);
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: "{}",
    });
  });

  const email = "obs-browser-" + Date.now() + "@example.test";
  await registerWithPassword(page, email);

  const sql = postgres(localSupabase().dbUrl, {
    max: 1,
    connect_timeout: 2,
    idle_timeout: 1,
  });
  try {
    await sql`
      update public.profiles
      set display_name = 'OBS Browser Tester'
      where id = (select id from auth.users where lower(email) = lower(${email}))
    `;
  } finally {
    await sql.end({ timeout: 1 });
  }
  await page.goto("/projects");
  await page.waitForURL(/\/projects(?:$|[/?#])/);

  umamiPayloads.length = 0;
  sentryBodies.length = 0;
  const dynamicPath =
    "/projects/" + PROJECT_ID + "/tasks/" + TASK_ID + "?token=fake#private";
  await page.goto(dynamicPath);

  await expect
    .poll(
      () =>
        umamiPayloads.some(
          (payload) => payload.url === "/projects/:projectId/tasks/:taskId",
        ),
      { timeout: 10_000 },
    )
    .toBe(true);

  const pageview = [...umamiPayloads]
    .reverse()
    .find((payload) => payload.url === "/projects/:projectId/tasks/:taskId");
  expect(pageview).toEqual({
    website: "obs-e2e-site",
    url: "/projects/:projectId/tasks/:taskId",
    title: "任务详情",
  });

  const serializedPageviews = JSON.stringify(umamiPayloads);
  expect(serializedPageviews).not.toContain(PROJECT_ID);
  expect(serializedPageviews).not.toContain(TASK_ID);
  expect(serializedPageviews).not.toContain("token=fake");
  expect(serializedPageviews).not.toContain(FAKE_TITLE);

  await page.goBack();
  await page.waitForURL(/\/projects(?:$|[/?#])/);
  umamiPayloads.length = 0;
  await page.evaluate((title) => {
    document.title = title;
  }, FAKE_TITLE);
  await page.goForward();

  await expect
    .poll(
      () =>
        umamiPayloads.some(
          (payload) => payload.url === "/projects/:projectId/tasks/:taskId",
        ),
      { timeout: 10_000 },
    )
    .toBe(true);
  expect(JSON.stringify(umamiPayloads)).not.toContain(FAKE_TITLE);

  sentryBodies.length = 0;
  await page.evaluate(
    ({ email, token, otp }) => {
      window.setTimeout(() => {
        throw new Error(
          "Synthetic OBS error email=" +
            email +
            " token=" +
            token +
            " otp=" +
            otp,
        );
      }, 0);
    },
    { email: FAKE_EMAIL, token: FAKE_TOKEN, otp: FAKE_OTP },
  );

  await expect
    .poll(
      () =>
        sentryBodies.some((body) =>
          body.includes("[redacted sensitive message]"),
        ),
      { timeout: 10_000 },
    )
    .toBe(true);

  const serializedSentry = sentryBodies.join("\n");
  expect(serializedSentry).not.toContain(FAKE_EMAIL);
  expect(serializedSentry).not.toContain(FAKE_TOKEN);
  expect(serializedSentry).not.toContain(FAKE_OTP);
  expect(serializedSentry).not.toContain(PROJECT_ID);
  expect(serializedSentry).not.toContain(TASK_ID);
  expect(serializedSentry).not.toContain("token=fake");
  expect(serializedSentry).not.toContain(FAKE_TITLE);
  expect(serializedSentry).toContain("[redacted sensitive message]");
});
