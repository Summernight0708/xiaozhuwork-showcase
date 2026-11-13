import assert from "node:assert/strict";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { localSupabase, registerWithPassword } from "./local-supabase";

test("G task cancellation and voluntary abandon respect two-account authority and keep evidence", async ({
  page,
  browser,
}, testInfo) => {
  test.skip(
    testInfo.project.name !== "desktop-chromium",
    "Disposable isolated G database only",
  );
  test.setTimeout(190_000);
  const env = localSupabase();
  test.skip(
    env.apiUrl !== "http://127.0.0.1:55811",
    "Dedicated G database only",
  );
  const db = postgres(env.dbUrl, { max: 2 });
  const otherContext = await browser.newContext();
  async function login(target: typeof page, email: string, label: string) {
    await target.goto("/login");
    await registerWithPassword(target, email);
    await expect(target).toHaveURL(/\/projects$/);
    await target.goto("/account/settings");
    await target.locator('input[name="displayName"]').fill(label);
    await target.getByRole("button", { name: "保存资料" }).click();
    await expect(target).toHaveURL(/\/projects$/);
    const id = (await db`select id from auth.users where email=${email}`)[0]
      ?.id;
    assert.ok(id);
    const session = await target.evaluate(() => {
      const value = Object.entries(window.localStorage).find(
        ([key]) => key.startsWith("sb-") && key.endsWith("-auth-token"),
      )?.[1];
      return value ? (JSON.parse(value) as { access_token: string }) : null;
    });
    assert.ok(session?.access_token);
    const api = createClient(env.apiUrl, env.anonKey, {
      global: { headers: { Authorization: `Bearer ${session.access_token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    return { id, api };
  }
  try {
    const leader = await login(
      page,
      `g-c-leader-${Date.now()}@example.test`,
      "G Cancellation Leader",
    );
    const other = await login(
      await otherContext.newPage(),
      `g-c-member-${Date.now()}@example.test`,
      "G Voluntary Member",
    );
    const project = (
      await db`
      insert into public.projects(name,deadline_at,created_by,leader_id,contribution_mode)
      values('G C two-account transition',now()+interval '12 days',
        ${leader.id}::uuid,${leader.id}::uuid,'weighted') returning id
    `
    )[0];
    assert.ok(project);
    const projectId = project.id as string;
    await db`insert into public.project_members(project_id,user_id,role,member_state,is_observer)
      values(${projectId}::uuid,${leader.id}::uuid,'leader','active',false),
      (${projectId}::uuid,${other.id}::uuid,'member','active',false)`;
    const taskRows = await db`
      insert into public.tasks(project_id,title,created_by,assignee_id,deadline_at,
        status,weight,assignment_state,accepted_at,version)
      values(${projectId}::uuid,'Cancel does not penalize',${leader.id}::uuid,
        ${leader.id}::uuid,now()+interval '7 days','in_progress',4,
        'assigned',now()-interval '2 hours',1),
        (${projectId}::uuid,'Member voluntary abandonment',${leader.id}::uuid,
        ${other.id}::uuid,now()+interval '7 days','in_progress',3,
        'assigned',now()-interval '2 hours',1)
      returning id,title
    `;
    const cancelTask = taskRows.find(
      (t) => t.title === "Cancel does not penalize",
    );
    const abandonTask = taskRows.find(
      (t) => t.title === "Member voluntary abandonment",
    );
    assert.ok(cancelTask && abandonTask);
    // G accepted epoch fixture: direct SQL task inserts bypass the
    // application's acceptance RPC that normally records an epoch.
    const [acceptedEpoch] = await db`
      select private.followup_open_responsibility_epoch(
        ${projectId}::uuid,${abandonTask.id}::uuid,${other.id}::uuid,
        (select accepted_at from public.tasks where id=${abandonTask.id}::uuid),
        'G accepted epoch fixture'
      ) as id
    `;
    assert.ok(acceptedEpoch?.id);

    const unauthorized = await other.api.rpc("cmd_cancel_task", {
      p_project_id: projectId,
      p_task_id: cancelTask.id,
      p_reason: "not authorized",
      p_request_id: crypto.randomUUID(),
      p_expected_version: 1,
    });
    expect(
      unauthorized.error === null ? unauthorized.data?.ok === false : true,
    ).toBe(true);
    const { data: cancel, error: cancelError } = await leader.api.rpc(
      "cmd_cancel_task",
      {
        p_project_id: projectId,
        p_task_id: cancelTask.id,
        p_reason: "Project requirements changed",
        p_request_id: crypto.randomUUID(),
        p_expected_version: 1,
      },
    );
    expect(cancelError).toBeNull();
    expect(cancel?.ok).toBe(true);
    const [state] =
      await db`select status,cancel_reason,assignee_id from public.tasks
      where id=${cancelTask.id}::uuid`;
    assert.ok(state);
    expect(state.status).toBe("canceled");
    expect(state.cancel_reason).toBe("Project requirements changed");
    expect(state.assignee_id).toBe(leader.id);

    const [beforeEpoch] =
      await db`select id from public.task_responsibility_epochs
      where task_id=${abandonTask.id}::uuid and closed_at is null`;
    assert.ok(
      beforeEpoch,
      "Accepted member must have real responsibility epoch",
    );
    const { data: abandon, error: abandonError } = await other.api.rpc(
      "cmd_abandon_task_responsibility",
      {
        p_project_id: projectId,
        p_task_id: abandonTask.id,
        p_reason: "Cannot continue responsibility",
        p_request_id: crypto.randomUUID(),
        p_expected_version: 1,
      },
    );
    expect(abandonError).toBeNull();
    expect(abandon?.ok).toBe(true);
    const [newTask] =
      await db`select assignee_id,accepted_at,assignment_state,status
      from public.tasks where id=${abandonTask.id}::uuid`;
    assert.ok(newTask);
    expect(newTask.assignee_id).toBeNull();
    expect(newTask.accepted_at).toBeNull();
    expect(newTask.assignment_state).toBe("claimable");
    expect(newTask.status).toBe("not_started");
    const [closedEpoch] =
      await db`select closure_reason from public.task_responsibility_epochs
      where id=${beforeEpoch.id}::uuid`;
    assert.ok(closedEpoch);
    expect(closedEpoch.closure_reason).toBe("abandoned");

    const [events] = await db`
      select count(*)::int as total from public.business_events
      where project_id=${projectId}::uuid and event_type in
       ('task_canceled','task_responsibility_abandoned')
    `;
    assert.ok(events);
    expect(events.total).toBe(2);
    const [penalty] = await db`
      select count(*)::int as total from public.contribution_penalties
      where project_id=${projectId}::uuid
    `;
    assert.ok(penalty);
    expect(penalty.total).toBe(0);
  } finally {
    await otherContext.close();
    await db.end({ timeout: 5 });
  }
});
