import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";

import {
  E2E_PASSWORD,
  findAuthUsersByEmail,
  localSupabase,
  loginWithPassword,
  registerWithPassword,
  waitForOtp,
} from "./local-supabase";

const NEW_PASSWORD = "XiaozhuWork-e2e-new-password-2";

async function clearBrowserAuth(page: import("@playwright/test").Page) {
  await page.evaluate(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  await page.goto("/login");
}

async function seedOtpOnlyUser(email: string) {
  const env = localSupabase();
  const client = createClient(env.apiUrl, env.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const sent = await client.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: true },
  });
  expect(sent.error).toBeNull();

  const otp = await waitForOtp(email);
  const verified = await client.auth.verifyOtp({
    email,
    token: otp,
    type: "email",
  });
  expect(verified.error).toBeNull();
  expect(verified.data.user?.id).toBeTruthy();
  await client.auth.signOut();

  return verified.data.user!.id;
}

test("registers once and then uses password login", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium");
  const email = `auth-password-register-${Date.now()}@example.test`;

  await registerWithPassword(page, email, E2E_PASSWORD);
  const rows = await findAuthUsersByEmail(email);
  expect(rows).toHaveLength(1);

  await clearBrowserAuth(page);
  await loginWithPassword(page, email, E2E_PASSWORD);
  await expect(page).toHaveURL(/\/(?:projects|account\/settings)(?:$|[/?#])/);
});

test("historical OTP-only account keeps the same Auth UUID after setting password through register", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium");
  const email = `auth-password-legacy-${Date.now()}@example.test`;
  const originalId = await seedOtpOnlyUser(email);
  const before = await findAuthUsersByEmail(email);
  expect(before).toHaveLength(1);
  expect(before[0]!.id).toBe(originalId);

  await registerWithPassword(page, email, E2E_PASSWORD);

  const after = await findAuthUsersByEmail(email);
  expect(after).toHaveLength(1);
  expect(after[0]!.id).toBe(originalId);

  await clearBrowserAuth(page);
  await loginWithPassword(page, email, E2E_PASSWORD);
});

test("recovery changes the password and rejects the old password", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium");
  const email = `auth-password-recovery-${Date.now()}@example.test`;

  await registerWithPassword(page, email, E2E_PASSWORD);
  await clearBrowserAuth(page);

  await page.goto("/forgot-password");
  await page.locator('input[type="email"]').fill(email);
  await page.getByRole("button", { name: "发送验证码" }).click();
  const otp = await waitForOtp(email);
  await page.locator("#otp-code").fill(otp);
  await page.getByRole("button", { name: "验证邮箱" }).click();

  const newPasswordInputs = page.locator('input[autocomplete="new-password"]');
  await newPasswordInputs.nth(0).fill(NEW_PASSWORD);
  await newPasswordInputs.nth(1).fill(NEW_PASSWORD);
  await page.getByRole("button", { name: "更新密码" }).click();
  await page.waitForURL(/\/(?:projects|account\/settings)(?:$|[/?#])/);

  await clearBrowserAuth(page);
  await page.locator('input[type="email"]').fill(email);
  await page.locator('input[type="password"]').fill(E2E_PASSWORD);
  const oldPasswordResponse = page.waitForResponse(
    (response) =>
      response.url().includes("/auth/v1/token") &&
      response.request().method() === "POST",
  );
  await page.getByRole("button", { name: "登录", exact: true }).click();
  expect((await oldPasswordResponse).ok()).toBe(false);
  await expect(page).toHaveURL(/\/login/);

  await loginWithPassword(page, email, NEW_PASSWORD);
});

test("recovery for a missing email does not create an Auth user", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium");
  const email = `auth-password-missing-${Date.now()}@example.test`;
  expect(await findAuthUsersByEmail(email)).toHaveLength(0);

  await page.goto("/forgot-password");
  await page.locator('input[type="email"]').fill(email);
  await page.getByRole("button", { name: "发送验证码" }).click();
  await expect(
    page.getByText("如果该邮箱存在，我们已发送验证码"),
  ).toBeVisible();

  expect(await findAuthUsersByEmail(email)).toHaveLength(0);
});
