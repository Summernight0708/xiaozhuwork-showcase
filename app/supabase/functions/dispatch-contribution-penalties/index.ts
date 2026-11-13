// Service-only cron endpoint; requires both JWT/service role and a separate
// high-entropy scheduler secret. No browser should call this function.
import { createClient } from "npm:@supabase/supabase-js@2";
const encoder = new TextEncoder();
function equalSecret(received: string, expected: string): boolean {
  const a = encoder.encode(received),
    b = encoder.encode(expected);
  let mismatch = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    mismatch |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return mismatch === 0;
}
Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST")
    return new Response("Method Not Allowed", { status: 405 });
  const secret = Deno.env.get("CONTRIBUTION_PENALTY_CRON_SECRET");
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret || secret.length < 32 || !url || !key)
    return new Response("Scheduler not configured", { status: 503 });
  if (
    !equalSecret(
      request.headers.get("x-contribution-penalty-secret") ?? "",
      secret,
    )
  )
    return new Response("Forbidden", { status: 403 });
  try {
    const client = createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await client.rpc(
      "dispatch_contribution_penalty_events_service",
      {
        p_batch_limit: 100,
      },
    );
    if (error) {
      console.error("Contribution dispatch failed", error.code);
      return new Response("Dispatch failed", { status: 500 });
    }
    return Response.json({ ok: true, summary: data });
  } catch {
    console.error("Unexpected contribution dispatch failure");
    return new Response("Dispatch failed", { status: 500 });
  }
});
