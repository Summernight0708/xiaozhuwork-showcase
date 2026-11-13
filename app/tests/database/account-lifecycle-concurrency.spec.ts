import postgres from "postgres";
import { describe, expect, it } from "vitest";

const isolatedUrl = process.env.XIAOZHUWORK_F_LIFECYCLE_DB_URL;
const describeIsolated = isolatedUrl ? describe : describe.skip;

describeIsolated(
  "F account lifecycle concurrency (isolated disposable DB only)",
  () => {
    it("serializes identical concurrent deletion requests", async () => {
      const url = isolatedUrl!;
      const admin = postgres(url, { max: 2 });
      const a = postgres(url, { max: 1 });
      const b = postgres(url, { max: 1 });
      const userId = "f5000000-0000-0000-0000-000000000001";
      const requestId = "f6000000-0000-0000-0000-000000000001";
      try {
        await admin`insert into auth.users(id,email) values (${userId},'f-concurrency@example.test') on conflict(id) do nothing`;
        await admin`insert into auth.sessions(id,user_id) values (${userId},${userId})`;
        const call = (db: typeof a) =>
          db.begin(async (tx) => {
            await tx`select set_config('request.jwt.claim.sub',${userId},true)`;
            await tx`select set_config('request.jwt.claims',${JSON.stringify({ session_id: userId })},true)`;
            await tx.unsafe("set local role authenticated");
            const [row] =
              await tx`select public.cmd_request_account_deletion(${requestId}::uuid,0) as result`;
            return row!.result as { ok: boolean; replayed: boolean };
          });
        const result = await Promise.all([call(a), call(b)]);
        expect(result.every((x) => x.ok)).toBe(true);
        expect(result.map((x) => x.replayed).sort()).toEqual([false, true]);
        const [count] =
          await admin`select count(*)::int as n from public.account_lifecycle_requests where user_id=${userId}`;
        expect(count?.n).toBe(1);
      } finally {
        // Keep other legacy pgTAP suites' empty-database assumptions intact.
        await admin`delete from public.account_lifecycle_requests where user_id=${userId}`;
        await admin`delete from private.account_lifecycle_audit where user_id=${userId}`;
        await admin`delete from public.command_requests where actor_id=${userId}`;
        await admin`delete from auth.users where id=${userId}`;
        await Promise.all([a.end(), b.end(), admin.end()]);
      }
    });
  },
);
