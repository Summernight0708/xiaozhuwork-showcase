import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";

import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const PROJECT_ID = "e2000000-0000-0000-0000-000000000001";
const TASK_ID = "e3000000-0000-0000-0000-000000000001";
const REPORT_ID = "e8000000-0000-4000-8000-000000000001";
const ITEM_ID = "e9000000-0000-0000-0000-000000000001";
const PASSWORD = "Day4-report-export-2026!";
const DISCLAIMER = "仅供参考，不代表教师评分或成员能力评价";

function utf16BeHex(value: string) {
  return [...value]
    .map((character) =>
      (character.codePointAt(0) ?? 0x3f)
        .toString(16)
        .padStart(4, "0")
        .toUpperCase(),
    )
    .join("");
}

function localSupabase() {
  const command =
    process.platform === "win32"
      ? (process.env.ComSpec ?? "cmd.exe")
      : "corepack";
  const args =
    process.platform === "win32"
      ? [
          "/d",
          "/s",
          "/c",
          "corepack",
          "pnpm",
          "exec",
          "supabase",
          "status",
          "-o",
          "env",
        ]
      : ["pnpm", "exec", "supabase", "status", "-o", "env"];
  const stdout = execFileSync(command, args, { encoding: "utf8" });
  const values = new Map<string, string>();
  for (const line of stdout.split(/\r?\n/)) {
    const match = /^([A-Z0-9_]+)="(.*)"$/.exec(line.trim());
    if (match) values.set(match[1]!, match[2]!);
  }
  const apiUrl = values.get("API_URL");
  const anonKey = values.get("ANON_KEY");
  const serviceRoleKey = values.get("SERVICE_ROLE_KEY");
  const dbUrl = values.get("DB_URL");
  if (!apiUrl || !anonKey || !serviceRoleKey || !dbUrl)
    throw new Error("missing local Supabase values");
  return { apiUrl, anonKey, serviceRoleKey, dbUrl };
}

describe("Day 4 report export Edge function", () => {
  const local = localSupabase();
  const sql = postgres(local.dbUrl, { max: 2 });
  const service = createClient(local.apiUrl, local.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const memberEmail = "day4-export-member-" + randomUUID() + "@example.test";
  const outsiderEmail =
    "day4-export-outsider-" + randomUUID() + "@example.test";
  let memberId = "";
  let outsiderId = "";
  let memberToken = "";
  let outsiderToken = "";

  async function cleanup() {
    await sql.unsafe("set session_replication_role = replica");
    try {
      for (const table of [
        "business_events",
        "command_requests",
        "contribution_confirmations",
        "contribution_items",
        "contribution_reports",
        "tasks",
        "project_members",
      ]) {
        await sql.unsafe(
          "delete from public." + table + " where project_id=$1",
          [PROJECT_ID],
        );
      }
      await sql.unsafe("delete from public.projects where id=$1", [PROJECT_ID]);
    } finally {
      await sql.unsafe("set session_replication_role = origin");
    }
  }

  beforeAll(async () => {
    await cleanup();
    const member = await service.auth.admin.createUser({
      email: memberEmail,
      password: PASSWORD,
      email_confirm: true,
    });
    const outsider = await service.auth.admin.createUser({
      email: outsiderEmail,
      password: PASSWORD,
      email_confirm: true,
    });
    if (member.error || !member.data.user)
      throw member.error ?? new Error("member create failed");
    if (outsider.error || !outsider.data.user)
      throw outsider.error ?? new Error("outsider create failed");
    memberId = member.data.user.id;
    outsiderId = outsider.data.user.id;
    const anon = createClient(local.apiUrl, local.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const memberSignIn = await anon.auth.signInWithPassword({
      email: memberEmail,
      password: PASSWORD,
    });
    const outsiderSignIn = await anon.auth.signInWithPassword({
      email: outsiderEmail,
      password: PASSWORD,
    });
    if (memberSignIn.error || !memberSignIn.data.session)
      throw memberSignIn.error ?? new Error("member sign in failed");
    if (outsiderSignIn.error || !outsiderSignIn.data.session)
      throw outsiderSignIn.error ?? new Error("outsider sign in failed");
    memberToken = memberSignIn.data.session.access_token;
    outsiderToken = outsiderSignIn.data.session.access_token;
    await sql.unsafe(
      "insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version,lifecycle_state) values($1,$2,now()+interval '10 days','weighted',$3,$3,2,'contribution_review')",
      [PROJECT_ID, "=FORMULA project", memberId],
    );
    await sql.unsafe(
      "insert into public.project_members(project_id,user_id,role,member_state,display_name_snapshot) values($1,$2,'leader','active',$3)",
      [PROJECT_ID, memberId, "@Member formula"],
    );
    await sql.unsafe(
      "insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,first_submitted_at,completed_at,version) values($1,$2,$3,$4,$4,now()+interval '2 days','completed',3,'assigned',now()-interval '3 hours',now()-interval '2 hours',now()-interval '1 hour',3)",
      [TASK_ID, PROJECT_ID, "+Task formula", memberId],
    );
    await sql.unsafe(
      "insert into public.contribution_reports(id,project_id,state,contribution_mode,source_project_version,eligible_member_count,required_confirmation_count,created_by,version) values($1,$2,'draft','weighted',1,1,1,$3,1)",
      [REPORT_ID, PROJECT_ID, memberId],
    );
    await sql.unsafe(
      "insert into public.contribution_items(id,report_id,project_id,task_id,member_user_id,member_display_name_snapshot,task_weight,share,contribution_value,task_title_snapshot,completed_at_snapshot) values($1,$2,$3,$4,$5,$6,3.0000,1.0000,3.0000,$7,now()-interval '1 hour')",
      [
        ITEM_ID,
        REPORT_ID,
        PROJECT_ID,
        TASK_ID,
        memberId,
        "@Member formula",
        "+Task formula",
      ],
    );
  });

  afterAll(async () => {
    try {
      await cleanup();
      if (memberId) await service.auth.admin.deleteUser(memberId);
      if (outsiderId) await service.auth.admin.deleteUser(outsiderId);
    } finally {
      await sql.end();
    }
  });

  function invoke(token: string | null, body: unknown) {
    return fetch(local.apiUrl + "/functions/v1/export-project-report", {
      method: "POST",
      headers: {
        apikey: local.anonKey,
        ...(token ? { authorization: "Bearer " + token } : {}),
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
  }

  test("authorized member receives a DRAFT CSV from authoritative snapshot without business writes", async () => {
    const before = await sql.unsafe(
      "select (select count(*)::integer from public.command_requests where project_id=$1) commands,(select count(*)::integer from public.business_events where project_id=$1) events",
      [PROJECT_ID],
    );
    const response = await invoke(memberToken, {
      reportId: REPORT_ID,
      format: "csv",
    });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-disposition")).toBe(
      'attachment; filename="xiaozhuwork-report-' + REPORT_ID + '.csv"',
    );
    const bytes = new Uint8Array(await response.arrayBuffer());
    expect([...bytes.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    const csv = new TextDecoder().decode(bytes);
    expect(csv).toContain("DRAFT");
    expect(csv).toContain(DISCLAIMER);
    expect(csv).toContain("'=FORMULA project");
    expect(csv).toContain("'+Task formula");
    expect(csv).toContain("'@Member formula");
    expect(csv).toContain("3.0000,3.00,1.0000,1.00,3.0000,3.00");
    const after = await sql.unsafe(
      "select (select count(*)::integer from public.command_requests where project_id=$1) commands,(select count(*)::integer from public.business_events where project_id=$1) events",
      [PROJECT_ID],
    );
    expect(after[0]).toEqual(before[0]);
  });

  test("formal PDF reflects authoritative formal state and disclaimer", async () => {
    const formalizedAt = "2026-09-29T12:34:56.000Z";
    await sql.unsafe(
      "insert into public.contribution_confirmations(report_id,project_id,user_id,confirmed_at) values($1,$2,$3,$4)",
      [REPORT_ID, PROJECT_ID, memberId, formalizedAt],
    );
    await sql.unsafe(
      "update public.contribution_reports set state='formal',formalized_at=$1,version=2,updated_at=$1 where id=$2",
      [formalizedAt, REPORT_ID],
    );
    await sql.unsafe(
      "update public.projects set lifecycle_state='completed',completed_at=$1,version=3,updated_at=$1 where id=$2",
      [formalizedAt, PROJECT_ID],
    );
    const response = await invoke(memberToken, {
      reportId: REPORT_ID,
      format: "pdf",
    });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("application/pdf");
    const bytes = new Uint8Array(await response.arrayBuffer());
    const raw = new TextDecoder("latin1").decode(bytes);
    expect(raw.startsWith("%PDF-1.4")).toBe(true);
    expect(raw).toContain("/Subtype /Type0");
    expect(raw).toContain("/Encoding /UniGB-UCS2-H");
    expect(raw).toContain("/ToUnicode");
    expect(raw).toContain(utf16BeHex(DISCLAIMER));
    expect(bytes.length).toBeGreaterThan(2_000);
    expect(bytes.length).toBeLessThan(100_000);
  });

  test("unauthenticated, outsider, and unsupported format requests fail safely", async () => {
    expect(
      (await invoke(null, { reportId: REPORT_ID, format: "csv" })).status,
    ).toBe(401);
    const outsider = await invoke(outsiderToken, {
      reportId: REPORT_ID,
      format: "csv",
    });
    expect(outsider.status).toBe(404);
    expect(await outsider.text()).not.toContain("FORMULA project");
    expect(
      (await invoke(memberToken, { reportId: REPORT_ID, format: "xlsx" }))
        .status,
    ).toBe(400);
  });
});
