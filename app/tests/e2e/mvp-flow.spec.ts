import { expect, test, type Page } from "@playwright/test";

import { registerWithPassword } from "./local-supabase";

const BASE_URL = "http://127.0.0.1:4173";

function futureLocalDate(days: number) {
  const date = new Date(Date.now() + days * 86_400_000);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

async function registerAccount(page: Page, email: string) {
  await registerWithPassword(page, email);
  await expect(page).toHaveURL(/\/(?:projects|account\/settings)(?:$|[/?#])/, {
    timeout: 15_000,
  });
}
async function setDisplayName(page: Page, displayName: string) {
  await page.goto(`${BASE_URL}/account/settings`);
  const field = page.locator('input[name="displayName"]');
  await field.fill(displayName);
  await page.getByRole("button", { name: "保存资料" }).click();
  // First-time profile completion persists asynchronously and then returns
  // to /projects. Wait for that navigation before verifying the saved value.
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });
  // Verify the authoritative saved value through a fresh account-page read.
  // The shell's account label can transiently render stale profile data while
  // the auth callback hydrates, even after the save has committed successfully.
  await page.goto(`${BASE_URL}/account/settings`);
  // A newly initialized GoTrue session can briefly leave this form blank
  // after a successful profile write. Re-load the real account page while
  // boundedly retrying; never populate or fake the expected value in the test.
  await expect(async () => {
    const savedName = page.locator('input[name="displayName"]');
    if ((await savedName.inputValue()) !== displayName) {
      await page.reload();
    }
    await expect(savedName).toHaveValue(displayName, { timeout: 5_000 });
  }).toPass({ timeout: 60_000, intervals: [500, 1_000, 2_000] });
  await page.goto(`${BASE_URL}/projects`);
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });
}

test("runs the real two-account MVP collaboration loop", async ({
  page,
  browser,
}, testInfo) => {
  test.skip(
    testInfo.project.name !== "desktop-chromium",
    "The heavy two-account closure runs once; mobile has the real-backend responsive smoke.",
  );
  // The end-to-end two-account closure exercises many serialized RPC, Storage,
  // and report-export operations. A shared CI runner can take substantially
  // longer than a dedicated local machine; keep every business assertion.
  test.setTimeout(540_000);

  const suffix = `${Date.now()}-${testInfo.workerIndex}`;
  const leaderEmail = `xiaozhuwork-e2e-leader-${suffix}@example.com`;
  const memberEmail = `xiaozhuwork-e2e-member-${suffix}@example.com`;
  const projectName = `E2E Project ${suffix}`;
  const taskTitle = `Evidence task ${suffix}`;
  const projectStart = futureLocalDate(1);
  const updatedProjectStart = futureLocalDate(2);

  await registerAccount(page, leaderEmail);
  await setDisplayName(page, "Leader One");
  console.info("[mvp-flow] leader authenticated");

  await page.goto(`${BASE_URL}/projects/create`);
  await page.getByPlaceholder("例如：计算机视觉课程设计").fill(projectName);
  await page.getByPlaceholder("可选").first().fill("E2E Course");
  await page.locator("#start-date").fill(projectStart);
  await page.locator("#deadline").fill(futureLocalDate(10));
  await page.getByRole("button", { name: "继续确认" }).click();
  await page.getByRole("button", { name: "确认创建" }).click();
  await expect(page).toHaveURL(/\/projects\/[0-9a-f-]+$/);

  const projectId = /\/projects\/([^/?#]+)/.exec(page.url())?.[1];
  expect(projectId).toBeTruthy();
  console.info("[mvp-flow] project created");

  await page.goto(`${BASE_URL}/projects/${projectId}/settings`);
  await expect(page.locator("#project-start-at")).toHaveValue(projectStart);
  await page.locator("#project-start-at").fill(updatedProjectStart);
  await page
    .locator(".form-grid textarea")
    .fill("E2E authoritative project settings.");
  await page.getByRole("button", { name: "保存设置" }).click();
  await expect(page.getByText("项目设置已保存")).toBeVisible();
  await page.reload();
  await expect(page.locator("#project-start-at")).toHaveValue(
    updatedProjectStart,
  );

  await page.goto(`${BASE_URL}/projects/${projectId}/invitations`);
  await page.getByRole("button", { name: "创建邀请链接" }).click();
  await page.locator(".invite-fields select").selectOption("approval");
  await page.getByRole("button", { name: "创建链接" }).click();
  const invitationUrl = await page
    .locator(".active-list code")
    .first()
    .textContent();
  expect(invitationUrl).toMatch(/\/invite\//);

  const memberContext = await browser.newContext();
  const memberPage = await memberContext.newPage();

  try {
    await registerAccount(memberPage, memberEmail);
    await setDisplayName(memberPage, "Member Two");

    await memberPage.goto(invitationUrl!);
    await memberPage.getByRole("button", { name: "提交加入申请" }).click();
    await expect(
      memberPage.getByRole("heading", { name: "加入申请已提交" }),
    ).toBeVisible();

    await page.reload();
    await expect(
      page.getByRole("heading", { name: "待处理加入申请" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "批准" }).click();
    await expect(page.getByText("已批准加入")).toBeVisible();
    console.info("[mvp-flow] invitation approved");

    await memberPage.goto(`${BASE_URL}/projects/${projectId}`);
    await expect(
      memberPage.getByRole("heading", { name: projectName }),
    ).toBeVisible();

    await page.goto(`${BASE_URL}/projects/${projectId}/members`);
    await page.getByRole("button", { name: /Member Two ·/ }).click();
    await page.getByLabel("管理 Member Two").click();
    const memberRoleSelect = page.locator(".management-menu select");
    await memberRoleSelect.selectOption("admin");
    await expect(page.getByText("成员角色已更新")).toBeVisible();
    await expect(memberRoleSelect).toHaveValue("admin");
    await memberRoleSelect.selectOption("observer");
    await expect(page.getByText("成员角色已更新")).toBeVisible();
    await expect(memberRoleSelect).toHaveValue("observer");
    await memberRoleSelect.selectOption("member");
    await expect(page.getByText("成员角色已更新")).toBeVisible();
    await expect(memberRoleSelect).toHaveValue("member");

    await page.goto(`${BASE_URL}/projects/${projectId}/tasks/new`);
    await page.getByLabel("任务名称 *").fill(taskTitle);
    await page.getByLabel("截止时间 *").fill(futureLocalDate(5));
    await page.getByLabel("指定成员").check();
    await page
      .locator(".select-field select")
      .selectOption({ label: "Member Two" });
    await page.getByRole("button", { name: "创建任务" }).click();
    await expect(page).toHaveURL(/\/tasks\/[0-9a-f-]+$/);

    const taskUrl = page.url();
    const taskId = /\/tasks\/([^/?#]+)/.exec(taskUrl)?.[1];
    expect(taskId).toBeTruthy();

    await page
      .locator(".inline-editor textarea")
      .fill("Edited through the controlled task command.");
    await page.getByRole("button", { name: "保存", exact: true }).click();
    await expect(page.getByText("操作成功")).toBeVisible();
    await expect(
      page.getByText("Edited through the controlled task command."),
    ).toBeVisible();

    await memberPage.goto(taskUrl);
    await memberPage.getByRole("button", { name: "接受指派" }).click();
    await expect(memberPage.getByText("操作成功")).toBeVisible();

    await memberPage.getByLabel("上传提交附件").setInputFiles({
      name: "report-v1.txt",
      mimeType: "text/plain",
      buffer: Buffer.from("XiaozhuWork E2E first evidence version.\n"),
    });
    await expect(
      memberPage.getByRole("article").getByText(/v1 · report-v1\.txt/),
    ).toBeVisible({ timeout: 20_000 });
    await memberPage
      .locator("#task-submission-section")
      .getByRole("button", { name: "提交验收" })
      .click();
    await expect(
      memberPage.locator("#task-submission-section").getByText("第 1 轮"),
    ).toBeVisible();

    await page.goto(`${BASE_URL}/projects/${projectId}/reviews`);
    await expect(page.getByRole("heading", { name: taskTitle })).toBeVisible();
    await page.getByRole("button", { name: "要求修改" }).click();
    await page.getByLabel("修改意见").fill("Please add a source.");
    await page.getByRole("button", { name: "确认要求修改" }).click();
    await expect(page.getByText("已要求修改")).toBeVisible();
    console.info("[mvp-flow] first review requested changes");
    console.info("[mvp-flow] navigating to the member file-history flow");

    await memberPage.goto(taskUrl);
    await expect(
      memberPage.getByText("Please add a source.").first(),
    ).toBeVisible();

    await memberPage.goto(`${BASE_URL}/projects/${projectId}/files`);
    const fileHistoryTrigger = memberPage.getByRole("button", {
      name: "打开文件 report-v1.txt",
    });
    await fileHistoryTrigger.click();
    const fileDialog = memberPage.getByRole("dialog", {
      name: "文件详情 report-v1.txt",
    });
    await expect(fileDialog).toBeVisible();
    console.info("[mvp-flow] original file history is visible");
    await expect(
      fileDialog.getByRole("button", { name: "关闭文件详情" }),
    ).toBeFocused();
    await fileDialog.getByRole("button", { name: "关闭文件详情" }).click();
    await expect(fileDialog).toBeHidden({ timeout: 15_000 });
    await expect(fileHistoryTrigger).toBeFocused();
    // The route and overlay complete asynchronously after explicit close. A bounded
    // re-open assertion identifies navigation/overlay failures at their source.
    await fileHistoryTrigger.click({ timeout: 15_000 });
    await expect(fileDialog).toBeVisible({ timeout: 15_000 });
    console.info("[mvp-flow] reopened original file drawer");
    const uploadNewVersion = fileDialog.getByRole("button", {
      name: "上传新版本",
    });
    await expect(uploadNewVersion).toBeEnabled({ timeout: 15_000 });
    await uploadNewVersion.click({ timeout: 15_000 });
    console.info("[mvp-flow] upload version action selected");
    // The button sets uploadMode/targetFileId then clicks the native input.
    // Set the real input bytes directly rather than waiting for a native
    // filechooser event, which can hang under headless popup transitions.
    await memberPage.locator('.upload-strip input[type="file"]').setInputFiles(
      {
        name: "report-v2.txt",
        mimeType: "text/plain",
        buffer: Buffer.from("XiaozhuWork E2E revised evidence with source.\n"),
      },
      { timeout: 15_000 },
    );
    console.info("[mvp-flow] new-version file input submitted");
    await expect(fileDialog.getByText("report-v2.txt")).toBeVisible({
      timeout: 20_000,
    });
    console.info("[mvp-flow] second file version uploaded");

    await memberPage.goto(taskUrl);
    await memberPage
      .getByRole("checkbox", { name: /report-v2\.txt · v2/ })
      .check();
    await memberPage
      .locator("#task-submission-section")
      .getByRole("button", { name: "提交验收" })
      .click();
    await expect(
      memberPage.locator("#task-submission-section").getByText("第 2 轮"),
    ).toBeVisible();
    console.info("[mvp-flow] second review submitted");

    await page.goto(`${BASE_URL}/projects/${projectId}/reviews`);
    await expect(page.getByText("第 2 轮验收")).toBeVisible();
    await page.getByRole("button", { name: "通过" }).click();
    await page.getByRole("button", { name: "确认通过" }).click();
    await expect(page.getByText("验收已通过")).toBeVisible();
    console.info("[mvp-flow] second review passed");

    await page.goto(taskUrl);
    await expect(page.locator(".task-detail-header .status-badge")).toHaveText(
      "已完成",
    );

    await page.goto(`${BASE_URL}/projects/${projectId}/files`);
    await page.getByRole("button", { name: "打开文件 report-v1.txt" }).click();
    const leaderFileDialog = page.getByRole("dialog", {
      name: "文件详情 report-v1.txt",
    });
    await leaderFileDialog
      .getByRole("button", { name: /标记最终 v2 report-v2\.txt/ })
      .click();
    await expect(page.getByText("已标记为最终成果")).toBeVisible();
    await expect(
      leaderFileDialog.getByText("最终成果", { exact: true }),
    ).toBeVisible();
    await leaderFileDialog
      .getByRole("button", { name: "关闭文件详情" })
      .click();
    await page.getByLabel("文件范围").selectOption("final");
    await expect(page.getByText("report-v1.txt").first()).toBeVisible();
    console.info("[mvp-flow] final file designated");

    await page.goto(`${BASE_URL}/projects/${projectId}/contributions`);
    await page.getByRole("button", { name: "生成贡献报告" }).click();
    await expect(
      page.getByRole("button", { name: "确认贡献报告" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "确认贡献报告" }).click();
    await expect(page.getByRole("button", { name: "你已确认" })).toBeDisabled();
    console.info("[mvp-flow] leader confirmed contribution report");

    await memberPage.goto(`${BASE_URL}/projects/${projectId}/contributions`);
    await memberPage.getByRole("button", { name: "确认贡献报告" }).click();
    await expect(
      memberPage.getByRole("button", { name: "导出 CSV" }),
    ).toBeVisible();
    console.info(
      "[mvp-flow] member report confirmed; testing CSV and PDF downloads",
    );

    const [csvDownload] = await Promise.all([
      memberPage.waitForEvent("download"),
      memberPage.getByRole("button", { name: "导出 CSV" }).click(),
    ]);
    expect(csvDownload.suggestedFilename()).toMatch(/\.csv$/);

    const [pdfDownload] = await Promise.all([
      memberPage.waitForEvent("download"),
      memberPage.getByRole("button", { name: "导出 PDF" }).click(),
    ]);
    expect(pdfDownload.suggestedFilename()).toMatch(/\.pdf$/);
    console.info("[mvp-flow] both reports exported");
  } finally {
    await memberContext.close();
  }
});
