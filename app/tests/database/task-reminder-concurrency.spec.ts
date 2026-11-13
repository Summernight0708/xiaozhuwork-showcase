import postgres from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl = process.env.SUPABASE_DB_URL ?? "";
const isolated = /\/xiaozhuwork_a_reminders_[a-z0-9]+(?:\?|$)/i.test(
  databaseUrl,
);
const taskId = "a4300000-0000-0000-0000-000000000001";
const projectId = "a4200000-0000-0000-0000-000000000001";
const userId = "a4100000-0000-0000-0000-000000000001";

describe.skipIf(!isolated)(
  "task reminder worker concurrency (isolated database only)",
  () => {
    const admin = postgres(databaseUrl, { max: 4 });
    beforeAll(async () => {
      await admin`insert into auth.users(id,email)
      values (${userId}::uuid,'deadline-race@example.test')`;
      await admin`insert into public.projects(id,name,deadline_at,leader_id,created_by)
      values (${projectId}::uuid,'Reminder concurrency',now()+interval '10 days',
        ${userId}::uuid,${userId}::uuid)`;
      await admin`insert into public.project_members(project_id,user_id,role,member_state,is_observer)
      values (${projectId}::uuid,${userId}::uuid,'leader','active',false)`;
      await admin`insert into public.tasks(id,project_id,title,assignee_id,deadline_at,status,assignment_state)
      values (${taskId}::uuid,${projectId}::uuid,'Concurrent due task',
        ${userId}::uuid,now()+interval '23 hours','in_progress','assigned')`;
    });
    afterAll(async () => {
      await admin.end();
    });

    test("two workers deliver a single occurrence even after retries", async () => {
      const workerA = postgres(databaseUrl, { max: 1 });
      const workerB = postgres(databaseUrl, { max: 1 });
      try {
        const [a, b] = await Promise.all([
          workerA`select private.dispatch_due_task_reminders(30,now()) as delivered`,
          workerB`select private.dispatch_due_task_reminders(30,now()) as delivered`,
        ]);
        expect(Number(a[0]?.delivered) + Number(b[0]?.delivered)).toBe(1);
        const retry =
          await admin`select private.dispatch_due_task_reminders(30,now()) as delivered`;
        expect(retry[0]?.delivered).toBe(0);
        const rows = await admin`select count(*)::integer as count
        from public.notifications where entity_id=${taskId}::uuid
          and notification_type='task_deadline_reminder'`;
        expect(rows[0]?.count).toBe(1);
        const delivered = await admin`select count(*)::integer as count
        from public.task_reminder_jobs where task_id=${taskId}::uuid
          and delivered_at is not null`;
        expect(delivered[0]?.count).toBe(1);
      } finally {
        await Promise.all([workerA.end(), workerB.end()]);
      }
    });

    test("deadline revisions retire old occurrences without resending delivered offsets", async () => {
      await admin`update public.tasks set deadline_at=now()+interval '1 hour'
      where id=${taskId}::uuid`;
      const result =
        await admin`select private.dispatch_due_task_reminders(30,now()) as delivered`;
      expect(result[0]?.delivered).toBe(1);
      const rows = await admin`select offset_seconds,deadline_revision
      from public.task_reminder_jobs where task_id=${taskId}::uuid
      and delivered_at is not null order by offset_seconds desc`;
      expect(rows.map((row) => Number(row.offset_seconds))).toEqual([
        86400, 7200,
      ]);
      expect(rows.map((row) => Number(row.deadline_revision))).toEqual([1, 2]);
    });
  },
);
