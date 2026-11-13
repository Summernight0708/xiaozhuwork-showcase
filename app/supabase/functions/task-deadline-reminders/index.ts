import { createClient } from "npm:@supabase/supabase-js@2";

const encode = (value: string) => new TextEncoder().encode(value);

function equalsSecret(received: string, expected: string): boolean {
  const a = encode(received);
  const b = encode(expected);
  let mismatch = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index += 1) {
    mismatch |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return mismatch === 0;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const secret = Deno.env.get("TASK_REMINDER_CRON_SECRET");
  const url = Deno.env.get("SUPABASE_URL");
  const roleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret || secret.length < 32 || !url || !roleKey) {
    console.error("Deadline reminder scheduler is not configured");
    return new Response("Service Unavailable", { status: 503 });
  }

  const received = request.headers.get("x-task-reminder-secret") ?? "";
  if (!equalsSecret(received, secret)) {
    return new Response("Forbidden", { status: 403 });
  }

  try {
    const client = createClient(url, roleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await client.rpc("dispatch_task_reminders_service", {
      p_batch_limit: 100,
    });
    if (error) {
      console.error("Deadline reminder dispatch failed", error.code);
      return new Response("Dispatch failed", { status: 500 });
    }
    return Response.json({ ok: true, delivered: data ?? 0 });
  } catch {
    console.error("Deadline reminder dispatch unexpectedly failed");
    return new Response("Dispatch failed", { status: 500 });
  }
});
