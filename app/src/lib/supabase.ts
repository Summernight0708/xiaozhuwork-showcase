import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import type { Database } from "@/types/database.generated";

const SUPABASE_URL_ENV = "VITE_SUPABASE_URL" as const;
const SUPABASE_KEY_REQUIREMENT =
  "VITE_SUPABASE_PUBLISHABLE_KEY / VITE_SUPABASE_ANON_KEY" as const;

type PublicEnv = Pick<
  ImportMetaEnv,
  | typeof SUPABASE_URL_ENV
  | "VITE_SUPABASE_PUBLISHABLE_KEY"
  | "VITE_SUPABASE_ANON_KEY"
>;
type MissingPublicEnv =
  typeof SUPABASE_URL_ENV | typeof SUPABASE_KEY_REQUIREMENT;

export type SupabaseEnvironmentStatus =
  | { configured: true; missing: [] }
  | { configured: false; missing: MissingPublicEnv[] };

function supabasePublicKey(env: PublicEnv) {
  return (
    env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ||
    env.VITE_SUPABASE_ANON_KEY?.trim() ||
    ""
  );
}

export function validateSupabaseEnvironment(
  env: PublicEnv = import.meta.env,
): SupabaseEnvironmentStatus {
  const missing: MissingPublicEnv[] = [];
  if (!env.VITE_SUPABASE_URL?.trim()) missing.push(SUPABASE_URL_ENV);
  if (!supabasePublicKey(env)) missing.push(SUPABASE_KEY_REQUIREMENT);
  return missing.length === 0
    ? { configured: true, missing: [] }
    : { configured: false, missing };
}

export function createSupabaseClient(
  env: PublicEnv = import.meta.env,
): SupabaseClient<Database> {
  const status = validateSupabaseEnvironment(env);
  if (!status.configured) {
    throw new Error(`Supabase 环境变量缺失：${status.missing.join("、")}`);
  }

  return createClient<Database>(
    env.VITE_SUPABASE_URL!.trim(),
    supabasePublicKey(env),
  );
}
