import assert from "node:assert/strict";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { localSupabase, registerWithPassword } from "./local-supabase";

test("G archive/restore UI enforces archived read-only against legacy command", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name !== "desktop-chromium",
    "Dedicated disposable Supabase only",
  );
  test.setTimeout(180_000);
  const env = localSupabase();
  test.skip(
    env.apiUrl !== "http://127.0.0.1:55811",
    "This test requires the disposable G Supabase sandbox",
  );
  const sql = postgres(env.dbUrl, { max: 1 });
  try {
    const email = `g-archiving-${Date.now()}@example.test`;
    await page.goto("/login");
    await registerWithPassword(page, email);
    await expect(page).toHaveURL(/\/projects$/);
    await page.goto("/account/settings");
    await page.locator('input[name="displayName"]').fill("G Archive Leader");
    await page.getByRole("button", { name: "保存资料" }).click();
    await expect(page).toHaveURL(/\/projects$/);
    const ownerId = (
      await sql`select id from auth.users where email=${email}`
    )[0]?.id;
    assert.ok(ownerId);
    const project = (
      await sql`
      insert into public.projects(name,deadline_at,created_by,leader_id)
      values('G real archive E2E',now()+interval '12 days',
        ${ownerId}::uuid,${ownerId}::uuid) returning id
    `
    )[0];
    assert.ok(project);
    const projectId = project.id as string;
    await sql`insert into public.project_members(project_id,user_id,role,member_state,is_observer)
      values(${projectId}::uuid,${ownerId}::uuid,'leader','active',false)`;
    const task = (
      await sql`
      insert into public.tasks(project_id,title,created_by,assignee_id,deadline_at,
      status,weight,assignment_state,version)
      values(${projectId}::uuid,'G archived task',
      ${ownerId}::uuid,${ownerId}::uuid,now()+interval '8 days',
      'not_started',3,'pending_acceptance',1) returning id
    `
    )[0];
    assert.ok(task);
    await page.goto(`/projects/${projectId}/settings`);
    const archive = page.locator(".archive-action");
    await expect(
      archive.getByRole("button", { name: "归档项目" }),
    ).toBeVisible();
    await archive.getByPlaceholder("例如：课程项目已结束").fill("课程验收完成");
    await archive.getByRole("button", { name: "归档项目" }).click();
    await page
      .getByRole("button", { name: "确认", exact: true })
      .last()
      .click();
    await expect(
      archive.getByText("本项目已归档，仅开放历史浏览、授权下载与导出。"),
    ).toBeVisible();
    const archived =
      await sql`select archived_at,version from public.projects where id=${projectId}::uuid`;
    assert.ok(archived[0]?.archived_at);

    // Browser JWT must not bypass the archived project write barrier.
    const token = await page.evaluate(() => {
      const record = Object.entries(window.localStorage).find(
        ([k]) => k.startsWith("sb-") && k.endsWith("-auth-token"),
      );
      return record
        ? (JSON.parse(record[1]) as { access_token: string })
        : null;
    });
    assert.ok(token?.access_token);
    const user = createClient(env.apiUrl, env.anonKey, {
      global: { headers: { Authorization: `Bearer ${token.access_token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: blocked, error: blockedError } = await user.rpc(
      "cmd_create_external_evidence",
      {
        p_project_id: projectId,
        p_task_id: task.id,
        p_https_url: "https://example.org/archived-document",
        p_description: "archived mutation attempt",
        p_request_id: crypto.randomUUID(),
        p_expected_version: 1,
      },
    );
    expect(blockedError === null ? blocked?.ok === false : true).toBe(true);
    const [evidenceCount] = await sql`
      select count(*)::int as total from public.task_external_evidence where project_id=${projectId}::uuid
    `;
    assert.ok(evidenceCount);
    expect(evidenceCount.total).toBe(0);

    await expect(
      archive.getByRole("button", { name: "延长保留" }),
    ).toBeVisible();
    await archive.getByRole("button", { name: "延长保留" }).click();
    await page
      .getByRole("button", { name: "确认", exact: true })
      .last()
      .click();
    await expect(archive.getByText(/保留至/)).toBeVisible();
    const [cycle] = await sql`
      select retain_until,restored_at from public.project_archive_cycles
      where project_id=${projectId}::uuid and restored_at is null
    `;
    assert.ok(cycle);
    assert.equal(cycle.restored_at, null);

    await archive.getByRole("button", { name: "恢复项目" }).click();
    await page
      .getByRole("button", { name: "确认", exact: true })
      .last()
      .click();
    await expect(
      archive.getByRole("button", { name: "归档项目" }),
    ).toBeVisible();
    const [restored] = await sql`
      select archived_at from public.projects where id=${projectId}::uuid
    `;
    assert.ok(restored);
    assert.equal(restored.archived_at, null);
  } finally {
    await sql.end({ timeout: 5 });
  }
});
