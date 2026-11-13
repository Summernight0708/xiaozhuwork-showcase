import { handleOpsRequest } from "./handler.ts";

function allowedOrigins(): string[] {
  return (Deno.env.get("OPS_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
}

Deno.serve((request) =>
  handleOpsRequest(request, {
    supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
    anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    allowedOrigins: allowedOrigins(),
  }),
);
