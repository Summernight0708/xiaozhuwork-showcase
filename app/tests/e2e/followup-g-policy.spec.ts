import { expect, test } from "@playwright/test";
import postgres from "postgres";
import { localSupabase, registerWithPassword } from "./local-supabase";

test("G requires explicit project policy and task share consent before an eligible epoch", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name !== "desktop-chromium",
    "Single isolated browser/DB fixture",
  );
  test.setTimeout(150_000);

  const email = `g-preconsent-${Date.now()}@example.test`;
  await page.goto("/login");
  await registerWithPassword(page, email);
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });

  const sql = postgres(localSupabase().dbUrl, { max: 1 });
  try {
    const rows = await sql`select id from auth.users where email=${email}`;
    const userId = rows[0]?.id as string | undefined;
    if (!userId) throw new Error("Expected local OTP account");

    await page.goto("/account/settings");
    const nameInput = page.locator('input[name="displayName"]');
    await nameInput.fill("Penalty Consent E2E");
    await page.getByRole("button", { name: "保存资料" }).click();
    await expect(page).toHaveURL(/\/projects$/, { timeout: 15_000 });

    const projectRows = await sql`
      insert into public.projects(name,deadline_at,created_by,leader_id,contribution_mode)
      values ('G consent browser fixture',now()+interval '12 days',
        ${userId}::uuid,${userId}::uuid,'weighted')
      returning id
    `;
    const projectId = projectRows[0]!.id as string;
    await sql`
      insert into public.project_members(project_id,user_id,role,member_state,is_observer)
      values(${projectId}::uuid,${userId}::uuid,'leader','active',false)
    `;

    await page.goto(`/projects/${projectId}/settings`);
    const panel = page.locator(".penalty-policy");
    await expect(panel.getByText(/当前：关闭/)).toBeVisible();
    await panel.locator(".penalty-policy__consent input").check();
    await panel.getByRole("button", { name: "记录本人同意" }).click();
    await expect(panel.getByText(/你已同意当前规则版本/)).toBeVisible();
    await panel.getByRole("button", { name: "全员同意后启用" }).click();
    await page
      .getByRole("button", { name: "确认", exact: true })
      .last()
      .click();
    await expect(panel.getByText(/当前：已启用/)).toBeVisible();
    const projectState =
      await sql`select auto_penalty_enabled from public.projects where id=${projectId}::uuid`;
    expect(projectState[0]?.auto_penalty_enabled).toBe(true);

    const taskRows = await sql`
      insert into public.tasks(project_id,title,created_by,assignee_id,deadline_at,
        status,weight,assignment_state,version)
      values(${projectId}::uuid,'G explicitly agreed four-star responsibility',
        ${userId}::uuid,${userId}::uuid,now()+interval '8 days',
        'not_started',4,'pending_acceptance',1)
      returning id
    `;
    const taskId = taskRows[0]!.id as string;
    await page.goto(`/projects/${projectId}/tasks/${taskId}`);
    const consent = page.locator(".expected-share");
    await expect(
      consent.getByText("接受任务前：确认预期贡献份额"),
    ).toBeVisible();
    await consent.getByPlaceholder("手动输入，例如 65").fill("100");
    await expect(consent.getByText(/4\.0000/)).toBeVisible();
    await consent.locator(".expected-share__check input").check();
    await consent.getByRole("button", { name: "记录本人事前份额" }).click();
    await expect(consent.getByText(/你已签署 100\.00%/)).toBeVisible();

    await sql`
      update public.tasks set accepted_at=now(),status='in_progress',
        assignment_state='assigned',version=version+1
      where id=${taskId}::uuid
    `;
    const epochs = await sql`
      select shares_confirmed,expected_share_bps_snapshot,accepted_expected_contribution
      from public.task_responsibility_epochs where task_id=${taskId}::uuid and closed_at is null
    `;
    expect(epochs).toHaveLength(1);
    expect(epochs[0]?.shares_confirmed).toBe(true);
    expect(epochs[0]?.expected_share_bps_snapshot).toBe(10000);
    expect(Number(epochs[0]?.accepted_expected_contribution)).toBe(4);
  } finally {
    await sql.end({ timeout: 5 });
  }
});
