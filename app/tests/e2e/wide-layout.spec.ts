import { expect, test } from "@playwright/test";

import { registerWithPassword } from "./local-supabase";

function futureLocalDate(days: number) {
  const date = new Date(Date.now() + days * 86_400_000);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

async function expectFullCanvas(page: import("@playwright/test").Page) {
  const metrics = await page.evaluate(() => {
    const main = document.querySelector<HTMLElement>(".shell-main");
    const content = document.querySelector<HTMLElement>(".xiaozhuwork-page");
    if (!main || !content) return null;

    const mainRect = main.getBoundingClientRect();
    const contentRect = content.getBoundingClientRect();
    return {
      mainX: mainRect.x,
      mainWidth: mainRect.width,
      contentX: contentRect.x,
      contentWidth: contentRect.width,
      viewportWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
    };
  });

  expect(metrics).not.toBeNull();
  expect(metrics!.contentWidth).toBeGreaterThanOrEqual(metrics!.mainWidth - 2);
  expect(Math.abs(metrics!.contentX - metrics!.mainX)).toBeLessThanOrEqual(2);
  expect(metrics!.scrollWidth).toBeLessThanOrEqual(metrics!.viewportWidth);
}

test("desktop app pages fill the AppShell canvas at wide breakpoints", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name === "mobile-chromium");
  test.setTimeout(300_000);

  const email = `xiaozhuwork-e2e-wide-${Date.now()}-${testInfo.workerIndex}@example.com`;
  await page.goto("/login");
  await registerWithPassword(page, email);
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });

  await page.goto("/account/settings");
  await page.locator('input[name="displayName"]').fill("Wide Layout E2E");
  await page.getByRole("button", { name: "保存资料" }).click();
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });

  await page.goto("/projects/create");
  await expect(page).toHaveURL(/\/projects\/create$/, { timeout: 15_000 });
  const projectNameInput = page.locator('input[name="projectName"]');
  await expect(projectNameInput).toBeVisible({ timeout: 15_000 });
  await projectNameInput.fill("Wide Layout Project");
  await page.locator('input[name="deadlineAt"]').fill(futureLocalDate(14));
  await page.getByRole("button", { name: "继续确认" }).click();
  await page.getByRole("button", { name: "确认创建" }).click();
  await expect(page).toHaveURL(/\/projects\/[^/]+$/, { timeout: 15_000 });

  const projectId = new URL(page.url()).pathname.split("/").filter(Boolean)[1];
  expect(projectId).toBeTruthy();

  const routes = [
    `/projects/${projectId}/settings`,
    "/notifications",
    "/account/settings",
    "/upgrade",
    "/help",
  ];

  for (const width of [1280, 1440, 1600]) {
    await page.setViewportSize({ width, height: 900 });
    for (const route of routes) {
      await page.goto(route);
      await expect(page.locator(".xiaozhuwork-page")).toBeVisible();
      await expectFullCanvas(page);
    }
  }
});
