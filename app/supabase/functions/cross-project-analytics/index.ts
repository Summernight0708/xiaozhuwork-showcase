import { handleCrossProjectRequest } from "./handler.ts";

Deno.serve((request) =>
  handleCrossProjectRequest(request, {
    supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
    anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  }),
);
