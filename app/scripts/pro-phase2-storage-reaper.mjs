/**
 * A-only reference-safe physical janitor. Scheduling is owned by G.
 *
 * Require PHASE2_REAP_ENABLED=true and explicit connection credentials.
 * The private SQL sweep first marks expired reservations rejected. Every
 * Storage delete then runs while holding project -> reservation DB locks,
 * with a fresh immutable-history reference check and post-delete verification.
 * No direct DELETE from storage.objects or speculative quota release occurs.
 */
import postgres from "postgres";
import { URL } from "node:url";

const enabled = process.env.PHASE2_REAP_ENABLED === "true";
const dbUrl = process.env.PHASE2_DB_URL;
const storageBase = process.env.PHASE2_STORAGE_API_URL;
const serviceKey = process.env.PHASE2_SERVICE_ROLE_KEY;
const limit = Number(process.env.PHASE2_REAP_LIMIT ?? "50");
const cutoff = process.env.PHASE2_REAP_BEFORE
  ? new Date(process.env.PHASE2_REAP_BEFORE)
  : new Date(Date.now() - 60 * 60 * 1000);
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;

if (
  !enabled ||
  !dbUrl ||
  !storageBase ||
  !serviceKey ||
  !Number.isInteger(limit) ||
  limit < 1 ||
  limit > 100 ||
  Number.isNaN(cutoff.getTime()) ||
  cutoff.getTime() > Date.now()
) {
  throw new Error(
    "Phase2 cleanup requires explicit opt-in, URLs, credentials, bounded limit and cutoff",
  );
}
const base = new URL(storageBase);
if (
  base.protocol !== "https:" &&
  !(
    base.protocol === "http:" &&
    ["localhost", "127.0.0.1"].includes(base.hostname)
  )
) {
  throw new Error(
    "Phase2 cleanup requires HTTPS (except isolated localhost tests)",
  );
}
const sql = postgres(dbUrl, { max: 1, prepare: false, connect_timeout: 10 });

let deleted = 0;
let failed = 0;
let alreadyGone = 0;

try {
  const [sweep] = await sql`select private.phase2_reap_expired_uploads(
    ${cutoff.toISOString()}::timestamptz, ${limit}::integer
  ) as result`;
  const rows = sweep?.result?.candidates;
  if (!Array.isArray(rows)) throw new Error("Unexpected cleanup RPC result");
  const candidates = rows.length;
  for (const row of rows) {
    try {
      if (
        !UUID.test(row.projectId) ||
        !UUID.test(row.reservationId) ||
        typeof row.objectPath !== "string" ||
        !row.objectPath.startsWith(
          `pending/${row.projectId}/${row.reservationId}/`,
        ) ||
        row.objectPath.includes("..")
      ) {
        throw new Error("Malformed cleanup candidate");
      }
      const outcome = await sql.begin(async (tx) => {
        const projects = await tx`select id from public.projects
          where id=${row.projectId}::uuid for update`;
        if (projects.length !== 1) return "skip";
        const reservations = await tx`select id,object_path,state,expires_at
          from public.file_upload_reservations
          where id=${row.reservationId}::uuid and project_id=${row.projectId}::uuid
          for update`;
        if (reservations.length !== 1) return "skip";
        const current = reservations[0];
        if (
          current.state !== "rejected" ||
          current.object_path !== row.objectPath ||
          new Date(current.expires_at) > cutoff
        )
          return "skip";
        const [refs] = await tx`select exists(
          select 1 from public.task_file_versions where object_path=${row.objectPath}
        ) as referenced`;
        if (refs.referenced) return "skip";
        const [physical] = await tx`select exists(
          select 1 from storage.objects
          where bucket_id='teamup-files' and name=${row.objectPath}
        ) as present`;
        if (!physical.present) return "gone";
        const response = await globalThis.fetch(
          `${base.toString().replace(/\/$/, "")}/storage/v1/object/teamup-files`,
          {
            method: "DELETE",
            headers: {
              apikey: serviceKey,
              authorization: `Bearer ${serviceKey}`,
              "content-type": "application/json",
            },
            body: JSON.stringify({ prefixes: [row.objectPath] }),
            signal: globalThis.AbortSignal.timeout(60_000),
          },
        );
        if (!response.ok)
          throw new Error(`Storage deletion failed (${response.status})`);
        const [after] = await tx`select exists(
          select 1 from storage.objects
          where bucket_id='teamup-files' and name=${row.objectPath}
        ) as present`;
        if (after.present)
          throw new Error("Storage object remained after deletion");
        return "deleted";
      });
      if (outcome === "deleted") deleted++;
      if (outcome === "gone") alreadyGone++;
    } catch {
      // Physical row remains billed when deletion or verification fails.
      failed++;
    }
  }
  console.log(
    JSON.stringify({
      scanned: candidates,
      deleted,
      alreadyGone,
      failed,
      skipped: candidates - deleted - alreadyGone - failed,
    }),
  );
  if (failed) process.exitCode = 1;
} finally {
  await sql.end({ timeout: 10 });
}
