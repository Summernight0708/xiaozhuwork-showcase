import assert from "node:assert/strict";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { localSupabase, registerWithPassword } from "./local-supabase";

test("G external evidence real two-account RLS, versioned edit, immutable revision, revoke", async ({
  page,
  browser,
}, testInfo) => {
  test.skip(
    testInfo.project.name !== "desktop-chromium",
    "Isolated disposable database only",
  );
  test.setTimeout(180_000);
  const env = localSupabase();
  test.skip(
    env.apiUrl !== "http://127.0.0.1:55811",
    "This test requires the disposable G Supabase sandbox",
  );
  const sql = postgres(env.dbUrl, { max: 2 });
  const outsiderContext = await browser.newContext();
  try {
    const email = `g-evidence-owner-${Date.now()}@example.test`;
    await page.goto("/login");
    await registerWithPassword(page, email);
    await expect(page).toHaveURL(/\/projects$/);
    await page.goto("/account/settings");
    await page.locator('input[name="displayName"]').fill("Evidence Owner E2E");
    await page.getByRole("button", { name: "保存资料" }).click();
    await expect(page).toHaveURL(/\/projects$/);
    const ownerId = (
      await sql`select id from auth.users where email=${email}`
    )[0]?.id;
    assert.ok(ownerId, "Test owner must exist");
    const [project] = await sql`
      insert into public.projects(name,deadline_at,created_by,leader_id)
      values('G D real evidence E2E',now()+interval '12 days',
        ${ownerId}::uuid,${ownerId}::uuid) returning id
    `;
    assert.ok(project, "Project fixture must exist");
    const projectId = project.id;
    await sql`insert into public.project_members(project_id,user_id,role,member_state,is_observer)
      values(${projectId}::uuid,${ownerId}::uuid,'leader','active',false)`;
    const [task] = await sql`
      insert into public.tasks(project_id,title,created_by,assignee_id,deadline_at,
        status,weight,assignment_state,version)
      values(${projectId}::uuid,'G external evidence task',
        ${ownerId}::uuid,${ownerId}::uuid,now()+interval '9 days',
        'in_progress',3,'assigned',1) returning id
    `;
    assert.ok(task, "Task fixture must exist");
    const taskId = task.id;
    await page.goto(`/projects/${projectId}/tasks/${taskId}`);
    const evidence = page.locator(".task-evidence");
    await expect(evidence.getByText("外部链接证据")).toBeVisible();
    await evidence.getByRole("button", { name: "添加外部证据" }).click();
    const draftUrl = `https://example.org/research?fixture=${taskId}`;
    await evidence.locator('input[type="url"]').fill(draftUrl);
    await evidence.locator("textarea").fill("初始提交资料");
    await evidence.getByRole("button", { name: "添加证据" }).click();
    await expect(evidence.getByText("初始提交资料")).toBeVisible();

    const [created] = await sql`
      select id,version,https_url,submitted_by from public.task_external_evidence
      where project_id=${projectId}::uuid and task_id=${taskId}::uuid
    `;
    assert.ok(created, "Evidence command must persist the created row");
    expect(created.version).toBe(1);
    expect(created.https_url).toBe(draftUrl);
    expect(created.submitted_by).toBe(ownerId);

    const outsiderPage = await outsiderContext.newPage();
    const outsiderEmail = `g-evidence-outsider-${Date.now()}@example.test`;
    await outsiderPage.goto("/login");
    await registerWithPassword(outsiderPage, outsiderEmail);
    await expect(outsiderPage).toHaveURL(/\/projects$/);
    const outsiderSession = await outsiderPage.evaluate(() => {
      const stored = Object.entries(window.localStorage).find(
        ([key]) => key.startsWith("sb-") && key.endsWith("-auth-token"),
      );
      return stored
        ? (JSON.parse(stored[1]) as { access_token: string })
        : null;
    });
    expect(outsiderSession?.access_token).toBeTruthy();
    const stranger = createClient(env.apiUrl, env.anonKey, {
      global: {
        headers: { Authorization: `Bearer ${outsiderSession!.access_token}` },
      },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: foreignRows, error: foreignReadError } = await stranger
      .from("task_external_evidence")
      .select("id")
      .eq("project_id", projectId);
    expect(foreignReadError).toBeNull();
    expect(foreignRows).toEqual([]);
    const { data: forbidden } = await stranger.rpc(
      "cmd_remove_external_evidence",
      {
        p_project_id: projectId,
        p_evidence_id: created.id,
        p_request_id: crypto.randomUUID(),
        p_expected_version: 1,
      },
    );
    expect(forbidden?.ok).toBe(false);

    await evidence.getByRole("button", { name: "编辑" }).click();
    await evidence.locator("textarea").fill("修订过的证据说明");
    await evidence.getByRole("button", { name: "保存修改" }).click();
    await expect(evidence.getByText("修订过的证据说明")).toBeVisible();
    const [afterEdit] =
      await sql`select version,description from public.task_external_evidence
      where id=${created.id}::uuid`;
    assert.ok(afterEdit, "Updated evidence must remain present");
    expect(afterEdit.version).toBe(2);

    await evidence.getByRole("button", { name: "查看修订记录" }).click();
    await expect(evidence.getByText(/第 1 版/)).toBeVisible();
    await evidence.getByRole("button", { name: "收起" }).click();

    await evidence.getByRole("button", { name: "撤销链接" }).click();
    await page
      .getByRole("button", { name: "确认", exact: true })
      .last()
      .click();
    await expect(evidence.getByText("修订过的证据说明")).toHaveCount(0);
    const [revoked] =
      await sql`select version,revoked_at from public.task_external_evidence
      where id=${created.id}::uuid`;
    assert.ok(revoked, "Revoked evidence history must be preserved");
    expect(revoked.version).toBe(3);
    expect(revoked.revoked_at).toBeTruthy();
    const [revisionCount] = await sql`
      select count(*)::int as total from public.task_external_evidence_revisions
      where evidence_id=${created.id}::uuid`;
    assert.ok(revisionCount);
    expect(revisionCount.total).toBe(2);
  } finally {
    await outsiderContext.close();
    await sql.end({ timeout: 5 });
  }
});
