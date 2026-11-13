import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { readSupabaseBrowserEnvironment } from "@shared/supabase/environment";

let client: SupabaseClient | undefined;

export function getOpsSupabase(): SupabaseClient {
  if (client) return client;

  const env = readSupabaseBrowserEnvironment(import.meta.env);
  if (!env.configured) {
    throw new Error("Ops Supabase public environment is not configured");
  }

  client = createClient(env.url, env.key, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  });
  return client;
}

export function resetOpsSupabaseForTests(): void {
  client = undefined;
}
