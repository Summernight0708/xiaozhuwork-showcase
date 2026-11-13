import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

// G-only: all writes, including the temporary capability whitelist, must be
// confined to the fresh integration database. Never point this at hosted DB.
const dbUrl = process.env.SUPABASE_DB_URL ?? "";
const apiUrl = process.env.XIAOZHUWORK_G_API_URL ?? "";
const enabled =
  process.env.XIAOZHUWORK_G_INTEGRATION_TEST === "1" &&
  /^postgres(?:ql)?:\/\/[^@]+@(?:localhost|127\.0\.0\.1):55512\/postgres$/.test(
    dbUrl,
  ) &&
  /^http:\/\/(?:localhost|127\.0\.0\.1):55511$/.test(apiUrl);
const db = enabled ? postgres(dbUrl, { max: 3 }) : null;
const suite = describe.skipIf(!enabled);
let actor = "";
let freeMember = "";
let actorToken = "";
let freeMemberToken = "";
const firstProject = "d2000000-0000-4000-8000-000000000001";
const secondProject = "d2000000-0000-4000-8000-000000000002";
const emptyProject = "d2000000-0000-4000-8000-000000000003";
const absentProject = "d2000000-0000-4000-8000-000000000099";
const projects = [firstProject, secondProject, emptyProject] as const;
const enabledCapabilities = [
  "file_full_history",
  "file_batch_rollback",
  "file_version_compare",
  "project_recovery_point",
  "project_analytics",
  "cross_project_overview",
  "cross_project_analytics",
];
const from = new Date(Date.now() - 7 * 86_400_000).toISOString();
const to = new Date(Date.now() - 1_000).toISOString();
let originalRelease = "";

function token(user: string): string {
  const current =
    user === actor ? actorToken : user === freeMember ? freeMemberToken : "";
  if (!current) throw new Error("No valid local GoTrue session for this user");
  return current;
}

async function requestRpc(
  rpc: string,
  params: Record<string, unknown>,
  user = actor,
) {
  const response = await fetch(apiUrl + "/rest/v1/rpc/" + rpc, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: process.env.XIAOZHUWORK_G_ANON_KEY ?? "",
      authorization: "Bearer " + token(user),
    },
    body: JSON.stringify(params),
  });
  return { status: response.status, body: await response.json() };
}

async function requestEdge(
  ids: string[] | null = [firstProject, secondProject],
  user = actor,
) {
  const response = await fetch(
    apiUrl + "/functions/v1/cross-project-analytics",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: process.env.XIAOZHUWORK_G_ANON_KEY ?? "",
        authorization: "Bearer " + token(user),
      },
      body: JSON.stringify({ from, to, projectIds: ids }),
      signal: AbortSignal.timeout(30_000),
    },
  );
  return { status: response.status, body: await response.json() };
}

async function setRelease(capabilities: string[]) {
  if (!db) throw new Error("G database is not available");
  // This method only accepts hard-coded server capability names.
  if (capabilities.some((name) => !enabledCapabilities.includes(name))) {
    throw new Error("Unexpected capability in G-only test");
  }
  const quoted = capabilities.map((name) => "'" + name + "'").join(",");
  await db.unsafe(
    `create or replace function private.capability_is_released(p_capability text)
    returns boolean language sql immutable security definer set search_path = ''
    as $$ select p_capability = any(array[${quoted}]::text[]) $$`,
  );
}

async function cleanup() {
  if (!db || !actor || !freeMember) return;
  await db.begin(async (tx) => {
    await tx.unsafe("set local session_replication_role = replica");
    await tx`delete from public.tasks where project_id in (${projects[0]}::uuid,${projects[1]}::uuid,${projects[2]}::uuid)`;
    await tx`delete from public.project_members where project_id in (${projects[0]}::uuid,${projects[1]}::uuid,${projects[2]}::uuid)`;
    await tx`delete from public.projects where id in (${projects[0]}::uuid,${projects[1]}::uuid,${projects[2]}::uuid)`;
    await tx`delete from public.account_entitlements where user_id in (${actor}::uuid,${freeMember}::uuid)`;
    await tx`delete from public.account_entitlement_audit where user_id in (${actor}::uuid,${freeMember}::uuid)`;
    await tx`delete from auth.users where id in (${actor}::uuid,${freeMember}::uuid)`;
  });
}

suite("G live C SQL / F Edge integration on isolated local Supabase", () => {
  beforeAll(async () => {
    if (!db) throw new Error("Integration database missing");
    if (
      !process.env.XIAOZHUWORK_G_ANON_KEY ||
      !process.env.XIAOZHUWORK_G_SERVICE_KEY
    ) {
      throw new Error("G local Supabase credentials missing");
    }
    const rows = await db`select pg_get_functiondef(
      'private.capability_is_released(text)'::regprocedure) as def`;
    originalRelease = rows[0]!.def as string;
    const authAdmin = createClient(
      apiUrl,
      process.env.XIAOZHUWORK_G_SERVICE_KEY,
      {
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    const anon = createClient(apiUrl, process.env.XIAOZHUWORK_G_ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const password = "G-integration-Supabase-2026!";
    for (const isPro of [true, false]) {
      const email =
        "g-cf-" +
        (isPro ? "pro" : "free") +
        "-" +
        crypto.randomUUID() +
        "@example.test";
      const created = await authAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      if (created.error || !created.data.user) {
        throw new Error("G local user creation failed");
      }
      const signed = await anon.auth.signInWithPassword({ email, password });
      if (signed.error || !signed.data.session) {
        throw new Error("G local GoTrue sign-in failed");
      }
      if (isPro) {
        actor = created.data.user.id;
        actorToken = signed.data.session.access_token;
      } else {
        freeMember = created.data.user.id;
        freeMemberToken = signed.data.session.access_token;
      }
    }
    for (const [index, project] of projects.entries()) {
      await db`insert into public.projects(id,name,leader_id,created_by,deadline_at)
        values (${project}::uuid,${"G C/F project " + index},
        ${actor}::uuid,${actor}::uuid,now()+interval '60 days')`;
      await db`insert into public.project_members(project_id,user_id,role,member_state)
        values (${project}::uuid,${actor}::uuid,'leader','active')`;
    }
    // Preserve the unique-leader invariant during simulated member revocation:
    // the Account Pro actor is a member, not the leader, of project two.
    await db.begin(async (tx) => {
      await tx`update public.projects set leader_id=${freeMember}::uuid
        where id=${secondProject}::uuid`;
      await tx`update public.project_members set role='member'
        where project_id=${secondProject}::uuid and user_id=${actor}::uuid`;
      await tx`insert into public.project_members(project_id,user_id,role,member_state)
        values (${secondProject}::uuid,${freeMember}::uuid,'leader','active')`;
    });
    await db`insert into public.project_members(project_id,user_id,role,member_state)
      values (${firstProject}::uuid,${freeMember}::uuid,'member','active')`;
    await db`insert into public.account_entitlements(
      user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
    ) values (${actor}::uuid,'pro','active',
      now()-interval '1 day',now()+interval '30 days',now(),
      ${actor}::uuid,'test',1)`;
    await db`insert into public.tasks(
      project_id,title,deadline_at,status,created_by,assignee_id,assignment_state,
      accepted_at,weight,created_at,completed_at
    ) values
      (${firstProject}::uuid,'G completed',now()+interval '2 days',
        'completed',${actor}::uuid,${actor}::uuid,'assigned',
        now()-interval '5 days',5,now()-interval '4 days',now()-interval '1 day'),
      (${firstProject}::uuid,'G overdue',now()-interval '1 day',
        'not_started',${actor}::uuid,null,'claimable',
        null,2,now()-interval '3 days',null),
      (${secondProject}::uuid,'G awaiting review',now()+interval '5 days',
        'awaiting_review',${actor}::uuid,${actor}::uuid,'assigned',
        now()-interval '2 days',4,now()-interval '2 days',null)`;
    await setRelease(enabledCapabilities);
  }, 40_000);

  afterAll(async () => {
    if (!db) return;
    try {
      if (originalRelease) await db.unsafe(originalRelease);
      await cleanup();
    } finally {
      await db.end({ timeout: 5 });
    }
  });

  it("combines actual C RPC results through live F Edge with exact six totals and UTC buckets", async () => {
    const args = { p_from: from, p_to: to };
    const first = await requestRpc("get_project_analytics", {
      ...args,
      p_project_id: firstProject,
    });
    const second = await requestRpc("get_project_analytics", {
      ...args,
      p_project_id: secondProject,
    });
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(first.body.ok).toBe(true);
    expect(second.body.ok).toBe(true);
    const merged = await requestEdge();
    expect(merged.status).toBe(200);
    expect(merged.body.ok).toBe(true);
    expect(merged.body.schemaVersion).toBe(1);
    expect(merged.body.projectCount).toBe(2);
    expect(merged.body.window).toEqual({
      from,
      to,
      bucket: "day",
      timezone: "UTC",
    });
    for (const key of [
      "taskTotal",
      "completedTasks",
      "overdueTasks",
      "awaitingReviewTasks",
      "blockedTasks",
      "completedInWindow",
    ] as const) {
      expect(merged.body.totals[key]).toBe(
        first.body.totals[key] + second.body.totals[key],
      );
    }
    expect(merged.body.totals).toEqual({
      taskTotal: 3,
      completedTasks: 1,
      overdueTasks: 1,
      awaitingReviewTasks: 1,
      blockedTasks: 0,
      completedInWindow: 1,
    });
    expect(merged.body.difficultyDistribution).toEqual(
      first.body.difficultyDistribution.map(
        (bucket: { stars: number | null; count: number }, i: number) => ({
          stars: bucket.stars,
          count: bucket.count + second.body.difficultyDistribution[i].count,
        }),
      ),
    );
    expect(merged.body.trends).toEqual(
      first.body.trends.map(
        (
          day: { day: string; created: number; completed: number },
          i: number,
        ) => ({
          day: day.day,
          created: day.created + second.body.trends[i].created,
          completed: day.completed + second.body.trends[i].completed,
        }),
      ),
    );
    expect(
      merged.body.projects.map((p: { projectId: string }) => p.projectId),
    ).toEqual([firstProject, secondProject]);
    expect(Math.abs(Date.parse(merged.body.asOf) - Date.now())).toBeLessThan(
      60_000,
    );
  }, 60_000);

  it("keeps null completion rate when all selected projects have no tasks", async () => {
    const result = await requestEdge([emptyProject]);
    expect(result.status).toBe(200);
    expect(result.body.totals.taskTotal).toBe(0);
    expect(result.body.completionRate).toBeNull();
  });

  it("rejects inaccessible IDs atomically and applies membership revocation immediately", async () => {
    const guessed = await requestEdge([firstProject, absentProject]);
    expect(guessed.body.ok).toBe(false);
    expect(guessed.body.code).toBe("NOT_FOUND_OR_NOT_AUTHORIZED");
    if (!db) throw new Error("G database missing");
    await db`update public.project_members set member_state='left',departed_at=now()
      where project_id=${secondProject}::uuid and user_id=${actor}::uuid`;
    try {
      const revoked = await requestEdge();
      expect(revoked.body.ok).toBe(false);
      expect(revoked.body.code).toBe("NOT_FOUND_OR_NOT_AUTHORIZED");
    } finally {
      await db`update public.project_members set member_state='active',departed_at=null
        where project_id=${secondProject}::uuid and user_id=${actor}::uuid`;
    }
  });

  it("does not confuse Project Pro with Account Pro", async () => {
    const direct = await requestRpc(
      "get_project_analytics",
      { p_project_id: firstProject, p_from: from, p_to: to },
      freeMember,
    );
    expect(direct.body.ok).toBe(true);
    const account = await requestEdge([firstProject], freeMember);
    expect(account.body.code).toBe("CAPABILITY_REQUIRES_PRO");
  });

  it("fails closed if the C capability is unavailable", async () => {
    await setRelease(
      enabledCapabilities.filter((c) => c !== "project_analytics"),
    );
    try {
      const unavailable = await requestEdge([firstProject]);
      expect(unavailable.body.code).toBe("SERVICE_UNAVAILABLE");
    } finally {
      await setRelease(enabledCapabilities);
    }
  });

  it("rejects over 100 projects before returning any partial aggregates", async () => {
    const ids = Array.from(
      { length: 101 },
      (_, i) => `d2000000-0000-4000-8000-${String(500 + i).padStart(12, "0")}`,
    );
    const result = await requestEdge(ids);
    expect(result.status).toBe(413);
    expect(result.body.code).toBe("QUERY_LIMIT_EXCEEDED");
  });
});
