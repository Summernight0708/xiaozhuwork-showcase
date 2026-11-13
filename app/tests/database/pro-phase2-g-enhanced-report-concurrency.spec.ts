import { randomUUID } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const dbUrl = process.env.SUPABASE_DB_URL ?? "";
const apiUrl = process.env.XIAOZHUWORK_G_API_URL ?? "";
const enabled =
  process.env.XIAOZHUWORK_G_ENHANCED_REPORT_TEST === "1" &&
  /^postgres(?:ql)?:\/\/[^@]+@(?:localhost|127\.0\.0\.1):55512\/postgres$/.test(
    dbUrl,
  ) &&
  /^http:\/\/(?:localhost|127\.0\.0\.1):55511$/.test(apiUrl);
const suite = describe.skipIf(!enabled);
const db = enabled ? postgres(dbUrl, { max: 2 }) : null;

const projectId = "be200000-0000-4000-8000-000000000001";
const taskId = "be300000-0000-4000-8000-000000000001";
const reportId = "be800000-0000-4000-8000-000000000001";
const itemId = "be900000-0000-4000-8000-000000000001";
let oldRelease = "";
let memberId = "";
let outsiderId = "";
let memberToken = "";
let outsiderToken = "";
let service: SupabaseClient | null = null;

async function cleanup() {
  if (!db) return;
  await db.begin(async (tx) => {
    await tx.unsafe("set local session_replication_role = replica");
    for (const table of [
      "business_events",
      "command_requests",
      "contribution_confirmations",
      "contribution_items",
      "contribution_reports",
      "tasks",
      "project_members",
    ]) {
      await tx.unsafe("delete from public." + table + " where project_id=$1", [
        projectId,
      ]);
    }
    await tx.unsafe("delete from public.projects where id=$1", [projectId]);
    if (memberId) {
      await tx`delete from public.account_entitlements where user_id=${memberId}::uuid`;
      await tx`delete from public.account_entitlement_audit where user_id=${memberId}::uuid`;
    }
  });
}

async function invoke(token: string | null, format: "csv" | "pdf") {
  const response = await fetch(
    apiUrl + "/functions/v1/export-enhanced-project-report",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: process.env.XIAOZHUWORK_G_ANON_KEY ?? "",
        ...(token ? { authorization: "Bearer " + token } : {}),
      },
      body: JSON.stringify({ reportId, format }),
      signal: AbortSignal.timeout(30_000),
    },
  );
  return response;
}

suite("G live enhanced-report HTTP canary on isolated local Supabase", () => {
  beforeAll(async () => {
    if (
      !db ||
      !process.env.XIAOZHUWORK_G_ANON_KEY ||
      !process.env.XIAOZHUWORK_G_SERVICE_KEY
    ) {
      throw new Error("G local enhanced-report environment missing");
    }
    const current = await db`select pg_get_functiondef(
      'private.capability_is_released(text)'::regprocedure) as def`;
    oldRelease = current[0]!.def as string;

    service = createClient(apiUrl, process.env.XIAOZHUWORK_G_SERVICE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const anon = createClient(apiUrl, process.env.XIAOZHUWORK_G_ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const password = "G-enhanced-report-2026!";
    for (const kind of ["member", "outsider"] as const) {
      const email = "g-enhanced-" + kind + "-" + randomUUID() + "@example.test";
      const created = await service.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      if (created.error || !created.data.user) {
        throw new Error("Local enhanced-report user creation failed");
      }
      const signed = await anon.auth.signInWithPassword({ email, password });
      if (signed.error || !signed.data.session) {
        throw new Error("Local enhanced-report sign-in failed");
      }
      if (kind === "member") {
        memberId = created.data.user.id;
        memberToken = signed.data.session.access_token;
      } else {
        outsiderId = created.data.user.id;
        outsiderToken = signed.data.session.access_token;
      }
    }

    await db.unsafe(
      "insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version,lifecycle_state,completed_at) values($1,$2,now()+interval '10 days','weighted',$3,$3,3,'completed',now()-interval '1 hour')",
      [projectId, "增强报告中文项目 🌟 café", memberId],
    );
    await db.unsafe(
      "insert into public.project_members(project_id,user_id,role,member_state,display_name_snapshot) values($1,$2,'leader','active',$3)",
      [projectId, memberId, "王同学"],
    );
    await db.unsafe(
      "insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,first_submitted_at,completed_at,version) values($1,$2,$3,$4,$4,now()+interval '2 days','completed',3,'assigned',now()-interval '3 hours',now()-interval '2 hours',now()-interval '1 hour',3)",
      [taskId, projectId, "增强报告任务 中文测试", memberId],
    );
    await db.unsafe(
      "insert into public.contribution_reports(id,project_id,state,contribution_mode,source_project_version,eligible_member_count,required_confirmation_count,created_by,formalized_at,version) values($1,$2,'formal','weighted',3,1,1,$3,now()-interval '1 hour',2)",
      [reportId, projectId, memberId],
    );
    await db.unsafe(
      "insert into public.contribution_items(id,report_id,project_id,task_id,member_user_id,member_display_name_snapshot,task_weight,share,contribution_value,task_title_snapshot,completed_at_snapshot) values($1,$2,$3,$4,$5,$6,3.0000,1.0000,3.0000,$7,now()-interval '1 hour')",
      [
        itemId,
        reportId,
        projectId,
        taskId,
        memberId,
        "王同学",
        "增强报告任务 中文测试",
      ],
    );
    await db.unsafe(
      "insert into public.contribution_confirmations(report_id,project_id,user_id,confirmed_at) values($1,$2,$3,now()-interval '1 hour')",
      [reportId, projectId, memberId],
    );
    await db`insert into public.account_entitlements(
      user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
    ) values(
      ${memberId}::uuid,'pro','active',now()-interval '1 day',
      now()+interval '30 days',now(),${memberId}::uuid,'test',1
    )`;
  }, 40_000);

  afterAll(async () => {
    if (!db) return;
    try {
      if (oldRelease) await db.unsafe(oldRelease);
      await cleanup();
      if (service && memberId) await service.auth.admin.deleteUser(memberId);
      if (service && outsiderId)
        await service.auth.admin.deleteUser(outsiderId);
    } finally {
      await db.end({ timeout: 10 });
    }
  });

  test("stays fail-closed before the local release simulation", async () => {
    const response = await invoke(memberToken, "csv");
    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({
      ok: false,
      code: "CAPABILITY_NOT_AVAILABLE",
    });
  });

  test("exports real CSV/PDF for Pro and rejects unauthorized readers after local simulation", async () => {
    if (!db) throw new Error("G database unavailable");
    await db.unsafe(`create or replace function private.capability_is_released(
      p_capability text) returns boolean language sql immutable security definer
      set search_path='' as $$
      select p_capability = any(array[
        'file_full_history','file_batch_rollback','file_version_compare',
        'project_recovery_point','enhanced_report'
      ]::text[]) $$`);

    const csvResponse = await invoke(memberToken, "csv");
    expect(csvResponse.status).toBe(200);
    expect(csvResponse.headers.get("content-type")).toContain("text/csv");
    const csvBytes = new Uint8Array(await csvResponse.arrayBuffer());
    expect([...csvBytes.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    const csv = new TextDecoder().decode(csvBytes);
    expect(csv).toContain("增强报告中文项目");
    expect(csv).toContain("王同学");
    expect(csv).toContain("member_snapshot_percentage_2dp");

    const pdfResponse = await invoke(memberToken, "pdf");
    expect(pdfResponse.status).toBe(200);
    expect(pdfResponse.headers.get("content-type")).toContain(
      "application/pdf",
    );
    const pdf = new Uint8Array(await pdfResponse.arrayBuffer());
    expect(new TextDecoder("latin1").decode(pdf.slice(0, 8))).toContain(
      "%PDF-1.4",
    );
    expect(pdf.byteLength).toBeGreaterThan(20_000);

    const outsider = await invoke(outsiderToken, "csv");
    expect(outsider.status).toBe(404);
    expect(await outsider.json()).toMatchObject({
      ok: false,
      code: "NOT_FOUND_OR_NOT_AUTHORIZED",
    });
    expect((await invoke(null, "csv")).status).toBe(401);
  }, 60_000);
});
