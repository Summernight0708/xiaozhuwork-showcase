import { expect, test } from "@playwright/test";

import { registerWithPassword } from "../e2e/local-supabase";

const future = (days: number) => {
  const value = new Date(Date.now() + days * 86_400_000);
  return new Date(value.getTime() - value.getTimezoneOffset() * 60_000)
    .toISOString()
    .slice(0, 16);
};

test("real-data workbench stays legible across themes and viewports", async ({
  page,
}, info) => {
  test.skip(info.project.name !== "desktop-chromium");
  test.setTimeout(240_000);
  const email = `xiaozhuwork-ui-review-${Date.now()}@example.com`;
  await registerWithPassword(page, email);
  await expect(page).toHaveURL(/\/account\/settings|\/projects$/, {
    timeout: 20_000,
  });
  if (new URL(page.url()).pathname.startsWith("/account/settings")) {
    await page.locator('input[name="displayName"]').fill("UI 视觉验收");
    await page.getByRole("button", { name: "保存资料" }).click();
    await expect(page).toHaveURL(/\/projects$/, { timeout: 20_000 });
  }

  await page.goto("/projects/create");
  await page
    .getByPlaceholder("例如：计算机视觉课程设计")
    .fill("UI 审查测试项目");
  await page.locator("#start-date").fill(future(1));
  await page.locator("#deadline").fill(future(12));
  await page.getByRole("button", { name: "继续确认" }).click();
  await page.getByRole("button", { name: "确认创建" }).click();
  await expect(page).toHaveURL(/\/projects\/[0-9a-f-]+$/, { timeout: 25_000 });
  const projectId = new URL(page.url()).pathname.split("/")[2]!;

  await page.goto(`/projects/${projectId}/tasks/new`);
  await page.getByLabel("任务名称 *").fill("团队资料整理与文档交付");
  await page.getByLabel("截止时间 *").fill(future(5));
  await page.getByRole("button", { name: "创建任务" }).click();
  await expect(page).toHaveURL(/\/tasks\/[0-9a-f-]+$/, { timeout: 25_000 });

  const taskDetailPath = new URL(page.url()).pathname;

  const screens = [
    ["project-create", "/projects/create"],
    ["task-create", `/projects/${projectId}/tasks/new`],
    ["task-detail", taskDetailPath],
    ["cross-project", "/workspace/cross-project"],
    ["projects", "/projects"],
    ["overview", `/projects/${projectId}`],
    ["tasks", `/projects/${projectId}/tasks`],
    ["files", `/projects/${projectId}/files`],
    ["reviews", `/projects/${projectId}/reviews`],
    ["contributions", `/projects/${projectId}/contributions`],
    ["settings", "/account/settings"],
    ["upgrade", "/upgrade"],
  ] as const;
  for (const theme of ["light", "dark"] as const) {
    await page.evaluate(
      (value) => localStorage.setItem("xiaozhuwork-appearance", value),
      theme,
    );
    for (const width of [375, 768, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      for (const [name, route] of screens) {
        await page.goto(route);
        await expect(page.locator(".xiaozhuwork-page")).toBeVisible();
        await expect(page.locator("html")).toHaveAttribute("data-theme", theme);
        if (
          width === 1440 &&
          (name === "project-create" || name === "task-create")
        ) {
          const bounds = await page
            .locator(".xiaozhuwork-page.form-page")
            .boundingBox();
          expect(bounds?.width ?? 0).toBeGreaterThan(1040);
        }
        if (name === "task-detail") {
          await expect(
            page.locator(".task-detail-header .status-badge"),
          ).not.toHaveText(
            /^(blocked|not_started|in_progress|awaiting_review)$/,
          );
        }
        await expect
          .poll(async () =>
            page.evaluate(
              () =>
                document.documentElement.scrollWidth -
                document.documentElement.clientWidth,
            ),
          )
          .toBeLessThanOrEqual(1);
        await page.screenshot({
          path: info.outputPath(`${name}-${theme}-${width}.png`),
          animations: "disabled",
        });
      }
    }
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/projects");
  await expect(page.locator(".global-nav a[href='/upgrade']")).toHaveCount(1);
  await expect(page.locator(".account-panel a[href='/upgrade']")).toHaveCount(
    0,
  );

  await page.setViewportSize({ width: 375, height: 900 });
  await page.goto(`/projects/${projectId}/files`);
  const disclosure = page.getByRole("button", { name: /^筛选/ });
  await expect(disclosure).toHaveAttribute("aria-expanded", "false");
  await disclosure.click();
  await expect(disclosure).toHaveAttribute("aria-expanded", "true");
  await page.getByRole("combobox", { name: "文件范围" }).selectOption("final");
  await expect(disclosure).toContainText("已启用");
  await page.goto(`/projects/${projectId}/tasks`);
  const more = page.getByRole("button", { name: /^更多筛选/ });
  await more.click();
  await expect(more).toHaveAttribute("aria-expanded", "true");
});
