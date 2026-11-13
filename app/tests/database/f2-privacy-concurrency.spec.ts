import postgres from "postgres";
import { describe, expect, it } from "vitest";

const url = process.env.XIAOZHUWORK_F2_PRIVACY_DB_URL;
const isolated = url ? describe : describe.skip;

isolated("F2 privacy review concurrency (owned disposable DB only)", () => {
  it("persists one manifest and one assessment audit under simultaneous retries", async () => {
    const target = new URL(url!);
    if (
      target.hostname !== "127.0.0.1" ||
      !(
        target.port === "56122" ||
        (process.env.CI === "true" && target.port === "55512")
      ) ||
      target.pathname !== "/postgres"
    ) {
      throw new Error(
        "Refusing privacy test outside owned disposable F2 database",
      );
    }
    const db = postgres(url!, { max: 3 });
    const user = "fc100000-0000-0000-0000-000000000001";
    const scan = "fc200000-0000-0000-0000-000000000001";
    const assess = "fc200000-0000-0000-0000-000000000002";
    try {
      await db`insert into auth.users(id,email) values(${user},'f2-concurrency@example.test')`;
      await db`insert into public.account_lifecycle_requests(user_id,state,generation,version,requested_at,cancel_until)
        values(${user},'blocked',1,1,now()-interval '40 days',now()-interval '10 days')`;
      const invoke = (
        name: "lifecycle_scan_pii_service" | "lifecycle_assess_cleanup_service",
        requestId: string,
      ) =>
        db.begin(async (tx) => {
          await tx`select set_config('request.jwt.claim.role','service_role',true)`;
          await tx.unsafe("set local role service_role");
          const rows = await tx.unsafe(
            `select public.${name}($1::uuid,1,$2::uuid) as result`,
            [user, requestId],
          );
          return rows[0]!.result as {
            ok: boolean;
            replayed: boolean;
            manifestId?: string;
          };
        });
      const scans = await Promise.all([
        invoke("lifecycle_scan_pii_service", scan),
        invoke("lifecycle_scan_pii_service", scan),
      ]);
      expect(scans.every((item) => item.ok)).toBe(true);
      expect(scans.map((item) => item.replayed).sort()).toEqual([false, true]);
      expect(scans[0]!.manifestId).toBe(scans[1]!.manifestId);
      const assessments = await Promise.all([
        invoke("lifecycle_assess_cleanup_service", assess),
        invoke("lifecycle_assess_cleanup_service", assess),
      ]);
      expect(assessments.map((item) => item.replayed).sort()).toEqual([
        false,
        true,
      ]);
      const [counts] =
        await db`select count(*)::int n from private.account_lifecycle_audit
        where user_id=${user} and action in ('privacy_manifest_scanned','cleanup_assessed')`;
      expect(counts!.n).toBe(2);
      await db`update public.account_lifecycle_requests set state='canceled',canceled_at=now() where user_id=${user}`;
      const afterCancel = await invoke("lifecycle_scan_pii_service", scan);
      expect(afterCancel.ok).toBe(false);
    } finally {
      await db`delete from private.lifecycle_cleanup_review_attempts where user_id=${user}`;
      await db`delete from private.lifecycle_privacy_manifests where user_id=${user}`;
      await db`delete from private.account_lifecycle_audit where user_id=${user}`;
      await db`delete from public.account_lifecycle_requests where user_id=${user}`;
      await db`delete from auth.users where id=${user}`;
      await db.end();
    }
  });
});
