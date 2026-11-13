import { createClient } from "npm:@supabase/supabase-js@2";
const te = new TextEncoder();
function sameSecret(a: string, b: string): boolean {
  const x = te.encode(a),
    y = te.encode(b);
  let delta = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++)
    delta |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return delta === 0;
}
type WorkItem = {
  withdrawal_id: string;
  project_id: string;
  original_path: string;
  quarantine_path: string;
};
Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST")
    return new Response("Method Not Allowed", { status: 405 });
  const secret = Deno.env.get("FILE_WITHDRAWAL_CRON_SECRET");
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret || secret.length < 32 || !url || !key)
    return new Response("Not configured", { status: 503 });
  if (
    !sameSecret(request.headers.get("x-file-withdrawal-secret") ?? "", secret)
  )
    return new Response("Forbidden", { status: 403 });
  const client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.rpc(
    "list_pending_file_withdrawals_service",
    { p_batch_limit: 20 },
  );
  if (error) {
    console.error("Failed to fetch withdrawal queue", error.code);
    return new Response("Queue unavailable", { status: 500 });
  }
  let completed = 0,
    failed = 0;
  for (const row of (data as WorkItem[]) ?? []) {
    try {
      if (!row.withdrawal_id || !row.original_path || !row.quarantine_path) {
        failed++;
        continue;
      }
      // Supabase Storage's server-side move relocates bytes and deletes the original
      // object key: old signed URLs must no longer resolve after propagation.
      const { error: moveError } = await client.storage
        .from("teamup-files")
        .move(row.original_path, row.quarantine_path);
      if (moveError)
        console.warn(
          "Move outcome uncertain; verifying DB state",
          row.withdrawal_id,
        );
      // This database service RPC refuses completion until it sees source absent
      // and quarantine present; a second worker can safely reconcile a prior move.
      const { data: result, error: completeError } = await client.rpc(
        "cmd_complete_file_version_withdrawal_service",
        { p_withdrawal_id: row.withdrawal_id },
      );
      if (completeError || (result as { ok?: boolean })?.ok !== true) {
        failed++;
        console.error(
          "Quarantine incomplete",
          row.withdrawal_id,
          completeError?.code,
        );
      } else completed++;
    } catch {
      failed++;
      console.error("Quarantine worker unexpected failure", row.withdrawal_id);
    }
  }
  return Response.json(
    { ok: failed === 0, completed, failed },
    {
      status: failed === 0 ? 200 : 503,
      headers: { "cache-control": "no-store" },
    },
  );
});
