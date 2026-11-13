import { expect, test } from "@playwright/test";

import { registerWithPassword } from "./local-supabase";

function futureLocalDate(days: number) {
  const date = new Date(Date.now() + days * 86_400_000);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

test("dark appearance keeps login input text readable on its actual background", async ({
  page,
}) => {
  await page.goto("/login");
  await page.evaluate(() =>
    localStorage.setItem("xiaozhuwork-appearance", "dark"),
  );
  await page.reload();
  const contrast = await page
    .locator(".login-form .van-cell")
    .first()
    .evaluate((cell) => {
      const color = getComputedStyle(cell.querySelector("input") || cell).color;
      const background = getComputedStyle(cell).backgroundColor;
      const luminance = (value: string) => {
        const oklch = value.match(
          /^oklch\(\s*([\d.]+)%?\s+([\d.]+)\s+([-\d.]+)/i,
        );
        if (oklch) {
          const lightness = Number(oklch[1]) / (value.includes("%") ? 100 : 1);
          const chroma = Number(oklch[2]);
          const hue = (Number(oklch[3]) * Math.PI) / 180;
          const a = chroma * Math.cos(hue);
          const b = chroma * Math.sin(hue);
          const l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3;
          const m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3;
          const s = (lightness - 0.0894841775 * a - 1.291485548 * b) ** 3;
          const linear = [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
          ].map((part) => Math.max(0, Math.min(1, part)));
          return (
            linear[0]! * 0.2126 + linear[1]! * 0.7152 + linear[2]! * 0.0722
          );
        }

        const srgb = value
          .match(/[\d.]+/g)!
          .slice(0, 3)
          .map(Number)
          .map((part) => part / 255)
          .map((part) =>
            part <= 0.04045 ? part / 12.92 : ((part + 0.055) / 1.055) ** 2.4,
          );
        return srgb[0]! * 0.2126 + srgb[1]! * 0.7152 + srgb[2]! * 0.0722;
      };
      const [a, b] = [luminance(color), luminance(background)].sort(
        (x, y) => y - x,
      );
      return (a! + 0.05) / (b! + 0.05);
    });
  expect(contrast).toBeGreaterThanOrEqual(4.5);
});

test("download page stays in AppShell without a duplicate back button", async ({
  page,
}) => {
  const response = await page.goto("/download");
  expect(response?.ok()).toBe(true);
  await expect(page.locator(".topbar")).toBeVisible();
  await expect(page.getByRole("heading", { name: "Android 版" })).toBeVisible();
  await expect(page.locator(".download-back")).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "返回", exact: true }),
  ).toHaveCount(0);
});

test("serves the responsive productized login entry against local Supabase", async ({
  page,
}, testInfo) => {
  const response = await page.goto("/");

  expect(response?.ok()).toBe(true);
  await expect(page).toHaveTitle("小猪作业");
  await expect(page).toHaveURL(/\/login/);
  await expect(page.locator(".brand-name")).toHaveText("小猪作业");
  const productTitle = page.locator("#product-title");
  await expect(productTitle).toBeVisible();
  await expect(productTitle).toContainText("小猪作业，");
  await expect(productTitle).toContainText("让小组作业更清楚。");
  await expect(page.getByText("账号登录", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("button", { name: "登录", exact: true }),
  ).toBeEnabled();
  await expect(page.getByRole("link", { name: "忘记密码？" })).toBeVisible();
  await expect(page.getByRole("link", { name: "前往注册" })).toBeVisible();
  // The login page intentionally has no installer/download entry on any viewport.
  await expect(page.locator(".download-entry")).toHaveCount(0);

  const brandBox = await page.locator(".login-brand").boundingBox();
  const cardBox = await page.locator(".login-card").boundingBox();
  expect(brandBox).not.toBeNull();
  expect(cardBox).not.toBeNull();

  if (testInfo.project.name === "mobile-chromium") {
    expect(brandBox!.y).toBeLessThan(cardBox!.y);
    await expect(
      page.getByRole("button", { name: "登录", exact: true }),
    ).toBeInViewport();
  } else {
    expect(brandBox!.x).toBeLessThan(cardBox!.x);
  }

  const horizontalOverflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(horizontalOverflow).toBe(false);
});

test("renders the account upgrade page responsively without fixed pricing", async ({
  page,
}, testInfo) => {
  // The entitlement REST RPC may briefly be unavailable after local Auth/DB
  // reset. Keep the real account-plan assertions but give the existing retry
  // loop a full per-test budget beyond Playwright's 30s default.
  test.setTimeout(90_000);
  const email = `xiaozhuwork-e2e-upgrade-${testInfo.project.name}-${Date.now()}-${testInfo.workerIndex}@example.com`;
  await page.goto("/login");
  await registerWithPassword(page, email);
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });

  await page.goto("/account/settings");
  const displayName = page.locator('input[name="displayName"]');
  await displayName.fill("Upgrade E2E");
  await page.getByRole("button", { name: "保存资料" }).click();
  // Completing a new profile is asynchronous and returns to /projects;
  // navigating immediately cancels the profile-update request on Chromium.
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });

  await page.goto("/upgrade");
  const accountDownloadLink = page
    .locator(".account-menu")
    .getByRole("link", { name: "下载 Android 客户端", includeHidden: true });
  await expect(accountDownloadLink).toHaveAttribute("href", "/download");
  if (testInfo.project.name === "mobile-chromium") {
    await expect(accountDownloadLink).toBeHidden();
  }
  await expect(
    page
      .locator(".global-nav")
      .getByRole("link", { name: "方案与升级", includeHidden: true }),
  ).toHaveAttribute("href", "/upgrade");
  // The upgrade entry is intentionally global-only, not duplicated in the account dropdown.
  await expect(
    page
      .locator(".account-panel")
      .getByRole("link", { name: "方案与升级", includeHidden: true }),
  ).toHaveCount(0);

  await expect(page.getByRole("heading", { name: "方案与升级" })).toBeVisible();
  // A local Supabase startup can briefly reject an entitlement read even
  // after the preceding Auth/profile writes completed. Use the page's real
  // user-visible Retry action, bounded to 30 seconds. Never fake data or
  // drop the Free-plan/benefit assertions that follow.
  const planSummary = page.getByRole("heading", { name: "当前账号方案" });
  await expect(async () => {
    const retry = page.getByRole("button", { name: "重试" });
    if (await retry.isVisible()) {
      console.info("[upgrade-smoke] retrying transient entitlement load");
      await retry.click();
    }
    await expect(planSummary).toBeVisible({ timeout: 5_000 });
  }).toPass({ timeout: 60_000, intervals: [500, 1_000, 2_000] });
  await expect(page.getByText("当前有效方案为 Free。")).toBeVisible();
  await expect(page.getByText("观察者身份不触发项目 Pro。")).toBeVisible();
  await expect(page.getByText("your_wechat_id")).toBeVisible();

  await expect(page.getByText("以下权益均已正式上线。")).toBeVisible();

  if (testInfo.project.name === "mobile-chromium") {
    await expect(page.locator(".benefits-table-wrap")).toBeHidden();
    await expect(page.locator(".benefits-mobile")).toBeVisible();
  } else {
    await expect(page.locator(".benefits-table-wrap")).toBeVisible();
    await expect(page.locator(".benefits-mobile")).toBeHidden();
  }

  await expect(page.locator(".release-status")).toHaveCount(0);

  const text = await page.locator("body").innerText();
  expect(text).not.toMatch(/¥\s*\d/);
  expect(text).not.toContain("月付");
  expect(text).not.toContain("年付");

  // The complete Pro guide is readable even when the account remains Free.
  await page.goto("/help");
  await expect(page.getByRole("heading", { name: "使用指南" })).toBeVisible();
  // The revised help center groups 27 short tips into eight end-to-end guides;
  // keep the real search, legacy chapter, Pro, and example checks.
  await page.getByRole("searchbox", { name: "搜索指南及章节" }).fill("回滚");
  await page.getByRole("link", { name: /文件管理与存储/ }).click();
  await expect(
    page.getByRole("heading", { name: "文件管理与存储" }),
  ).toBeVisible();
  const rollbackChapter = page.locator("#guide-part-file-rollback");
  await expect(
    rollbackChapter.getByRole("heading", { name: /批量回滚与文件恢复点/ }),
  ).toBeVisible();
  await expect(rollbackChapter.getByText("Pro")).toBeVisible();
  await rollbackChapter.getByRole("button", { name: "查看示例" }).click();
  await expect(
    page.getByRole("dialog", { name: "版本回滚示例" }),
  ).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog", { name: "版本回滚示例" })).toHaveCount(
    0,
  );

  const horizontalOverflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(horizontalOverflow).toBe(false);
});

test("exposes the approved project More destinations on mobile", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name !== "mobile-chromium",
    "This interaction specifically verifies the mobile bottom navigation.",
  );

  const email = `xiaozhuwork-e2e-mobile-${Date.now()}-${testInfo.workerIndex}@example.com`;
  await page.goto("/login");
  await registerWithPassword(page, email);
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });

  await page.goto("/account/settings");
  const displayName = page.locator('input[name="displayName"]');
  await displayName.fill("Mobile E2E");
  await page.getByRole("button", { name: "保存资料" }).click();
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });
  await page.goto("/account/settings");
  await expect(page.locator('input[name="displayName"]')).toHaveValue(
    "Mobile E2E",
  );

  await page.locator(".account-menu summary").click();
  const accountMenu = page.getByRole("navigation", {
    name: "账号导航",
  });
  for (const label of ["个人资料"]) {
    await expect(
      accountMenu.getByRole("link", { name: label, exact: true }),
    ).toBeVisible();
  }
  await expect(accountMenu.getByRole("link", { name: "全局设置" })).toHaveCount(
    0,
  );
  await expect(
    accountMenu.getByRole("button", { name: "退出登录" }),
  ).toBeVisible();
  await page.locator(".account-menu summary").click();

  await page.goto("/projects/create");
  await page
    .getByPlaceholder("例如：计算机视觉课程设计")
    .fill("Mobile Navigation");
  await page.locator("#deadline").fill(futureLocalDate(7));
  await page.getByRole("button", { name: "继续确认" }).click();
  await page.getByRole("button", { name: "确认创建" }).click();
  await expect(page).toHaveURL(/\/projects\/[0-9a-f-]+$/);

  await page.locator(".mobile-more summary").click();
  for (const label of ["验收", "成员", "邀请", "贡献与报告", "项目设置"]) {
    await expect(
      page.getByRole("link", { name: label, exact: true }),
    ).toBeVisible();
  }
});
