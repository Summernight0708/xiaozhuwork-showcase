import { createHash, randomUUID } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import postgres, { type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import type { EvidenceCommandResult } from "../../src/features/external-evidence/types";

// No fallback to SUPABASE_DB_URL or the shared 54322 database. The runner stamps a fresh container.
const url = process.env.XIAOZHUWORK_D_DB_URL;
const enabled = !!url;
if (
  url &&
  !/^postgresql:\/\/postgres:[^@]+@127\.0\.0\.1:55444\/postgres$/.test(url)
) {
  throw new Error(
    "D concurrency requires its isolated loopback database on port 55444",
  );
}
const admin = enabled
  ? postgres(url!, {
      max: 4,
      connect_timeout: 5,
      connection: { statement_timeout: 15000 },
    })
  : null;
const racer = enabled
  ? postgres(url!, {
      max: 4,
      connect_timeout: 5,
      connection: {
        application_name: "external-evidence-racer",
        statement_timeout: 15000,
      },
    })
  : null;
type Fixture = { project: string; task: string; leader: string; actor: string };

beforeAll(async () => {
  if (!admin) return;
  const rows = await admin<
    { name: string; sha256: string }[]
  >`select name,sha256 from external_evidence_test.migrations order by name`;
  const names = readdirSync("supabase/migrations")
    .filter((name) => name.endsWith(".sql"))
    .sort();
  expect(rows.map((row) => row.name)).toEqual(names);
  for (const row of rows)
    expect(row.sha256).toBe(
      createHash("sha256")
        .update(readFileSync(`supabase/migrations/${row.name}`))
        .digest("hex"),
    );
  const [head] =
    await admin`select to_regprocedure('public.cmd_remove_external_evidence(uuid,uuid,uuid,integer)') is not null as installed`;
  expect(head!.installed).toBe(true);
});
afterAll(async () => {
  await Promise.all([admin?.end(), racer?.end()]);
});

async function fixture(): Promise<Fixture> {
  const f = {
    project: randomUUID(),
    task: randomUUID(),
    leader: randomUUID(),
    actor: randomUUID(),
  };
  await admin!.begin(async (tx) => {
    await tx`insert into auth.users(id,email) values(${f.leader},${f.leader + "@example.test"}),(${f.actor},${f.actor + "@example.test"})`;
    await tx`insert into public.projects(id,name,deadline_at,leader_id,created_by)
      values(${f.project},'D isolated race',now()+interval '20 days',${f.leader},${f.leader})`;
    await tx`insert into public.project_members(project_id,user_id,role) values
      (${f.project},${f.leader},'leader'),(${f.project},${f.actor},'member')`;
    await tx`insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,assignment_state,accepted_at)
      values(${f.task},${f.project},'D race',${f.leader},${f.actor},now()+interval '10 days','in_progress','assigned',now())`;
  });
  return f;
}
async function call(
  f: Fixture,
  action: "create" | "update" | "remove",
  entity: string,
  expected: number,
  request = randomUUID(),
  description = "Evidence",
) {
  return racer!.begin(async (tx) => {
    await tx`select set_config('request.jwt.claim.sub',${f.actor},true)`;
    await tx.unsafe("set local role authenticated");
    const args = [
      f.project,
      entity,
      ...(action === "remove"
        ? []
        : ["https://github.com/team/repo", description]),
      request,
      expected,
    ];
    const placeholders = args.map((_, i) => `$${i + 1}`).join(",");
    const rows = await tx.unsafe<{ result: EvidenceCommandResult }[]>(
      `select public.cmd_${action}_external_evidence(${placeholders}) as result`,
      args,
    );
    return rows[0]!.result;
  });
}
async function create(f: Fixture) {
  const result = await call(f, "create", f.task, 1);
  if (!result.ok) throw new Error(result.code);
  return result.data.evidenceId;
}
async function counts(f: Fixture) {
  const [row] = await admin!`select
    (select count(*)::int from public.task_external_evidence where project_id=${f.project}) as evidence,
    (select count(*)::int from public.task_external_evidence_revisions where project_id=${f.project}) as revisions,
    (select count(*)::int from public.business_events where project_id=${f.project} and event_type like 'external_evidence_%') as events`;
  return row!;
}
async function behindProjectLock(
  f: Fixture,
  mutation: (tx: TransactionSql) => Promise<unknown>,
  command: () => Promise<EvidenceCommandResult>,
) {
  let pending: Promise<EvidenceCommandResult> | undefined;
  await admin!.begin(async (tx) => {
    await tx`select id from public.projects where id=${f.project} for update`;
    await mutation(tx);
    pending = command();
    // A real database lock barrier, rather than assuming a sleep means the command has started.
    let blocked = false;
    for (let n = 0; n < 100; n++) {
      const [state] = await admin!`select exists(select 1 from pg_stat_activity
        where application_name='external-evidence-racer' and wait_event_type='Lock') as blocked`;
      if (state!.blocked) {
        blocked = true;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    expect(blocked).toBe(true);
  });
  return pending!;
}

describe.skipIf(!enabled)(
  "external evidence isolated database concurrency",
  () => {
    test("two creates with one task version allow exactly one", async () => {
      const f = await fixture();
      const results = await Promise.all([
        call(f, "create", f.task, 1),
        call(f, "create", f.task, 1),
      ]);
      expect(results.filter((r) => r.ok)).toHaveLength(1);
      expect(results.find((r) => !r.ok)).toMatchObject({
        code: "STALE_VERSION",
        currentVersion: 2,
      });
      expect(await counts(f)).toMatchObject({
        evidence: 1,
        revisions: 0,
        events: 1,
      });
    });
    test("empty description is valid and stored as an empty string", async () => {
      const f = await fixture();
      const result = await call(f, "create", f.task, 1, randomUUID(), "");
      expect(result.ok).toBe(true);
      const [row] =
        await admin!`select description,host from public.task_external_evidence where project_id=${f.project}`;
      expect(row).toMatchObject({ description: "", host: "github.com" });
      expect(await counts(f)).toMatchObject({ evidence: 1, events: 1 });
    });
    test("simultaneous same request replays with only one event", async () => {
      const f = await fixture();
      const request = randomUUID();
      const results = await Promise.all([
        call(f, "create", f.task, 1, request),
        call(f, "create", f.task, 1, request),
      ]);
      expect(results.every((r) => r.ok)).toBe(true);
      expect(results.map((r) => r.replayed).sort()).toEqual([false, true]);
      expect(await counts(f)).toMatchObject({ evidence: 1, events: 1 });
    });
    test("simultaneous reused request with changed payload fails", async () => {
      const f = await fixture();
      const request = randomUUID();
      const results = await Promise.all([
        call(f, "create", f.task, 1, request, "A"),
        call(f, "create", f.task, 1, request, "B"),
      ]);
      expect(results.filter((r) => r.ok)).toHaveLength(1);
      expect(results.find((r) => !r.ok)).toMatchObject({
        code: "IDEMPOTENCY_KEY_REUSED",
      });
      expect(await counts(f)).toMatchObject({ evidence: 1, events: 1 });
    });
    test("update versus remove uses the evidence version and preserves exactly one before-image", async () => {
      const f = await fixture();
      const evidence = await create(f);
      const results = await Promise.all([
        call(f, "update", evidence, 1),
        call(f, "remove", evidence, 1),
      ]);
      expect(results.filter((r) => r.ok)).toHaveLength(1);
      expect(results.find((r) => !r.ok)).toMatchObject({
        code: "STALE_VERSION",
        currentVersion: 2,
      });
      expect(await counts(f)).toMatchObject({ revisions: 1, events: 2 });
      const [snapshot] =
        await admin!`select description,version from public.task_external_evidence_revisions where evidence_id=${evidence}`;
      expect(snapshot).toMatchObject({ description: "Evidence", version: 1 });
    });
    test("duplicate remove requests replay without a second revocation", async () => {
      const f = await fixture();
      const evidence = await create(f);
      const request = randomUUID();
      const results = await Promise.all([
        call(f, "remove", evidence, 1, request),
        call(f, "remove", evidence, 1, request),
      ]);
      expect(results.every((r) => r.ok)).toBe(true);
      expect(results.filter((r) => r.replayed)).toHaveLength(1);
      expect(await counts(f)).toMatchObject({ revisions: 1, events: 2 });
    });
    test("archive committed while command waits blocks the write", async () => {
      const f = await fixture();
      const evidence = await create(f);
      const result = await behindProjectLock(
        f,
        async (tx) => {
          await tx`update public.projects set archived_at=now(),version=version+1 where id=${f.project}`;
        },
        () => call(f, "update", evidence, 1),
      );
      expect(result).toMatchObject({ ok: false, code: "PROJECT_NOT_ACTIVE" });
      expect(await counts(f)).toMatchObject({ revisions: 0, events: 1 });
    });
    test("member revocation committed while replay waits prevents disclosure", async () => {
      const f = await fixture();
      const request = randomUUID();
      await call(f, "create", f.task, 1, request);
      const result = await behindProjectLock(
        f,
        async (tx) => {
          await tx`update public.project_members set member_state='removed',departed_at=now() where project_id=${f.project} and user_id=${f.actor}`;
        },
        () => call(f, "create", f.task, 1, request),
      );
      expect(result).toMatchObject({
        ok: false,
        code: "NOT_FOUND_OR_NOT_AUTHORIZED",
      });
    });
    test("task cancellation committed ahead of an update freezes evidence", async () => {
      const f = await fixture();
      const evidence = await create(f);
      const result = await behindProjectLock(
        f,
        async (tx) => {
          await tx`update public.tasks set status='canceled',canceled_at=now(),cancel_reason='Changed requirements',version=version+1 where id=${f.task}`;
        },
        () => call(f, "update", evidence, 1),
      );
      expect(result).toMatchObject({ ok: false, code: "INVALID_TRANSITION" });
      expect(await counts(f)).toMatchObject({ revisions: 0, events: 1 });
    });
  },
);
