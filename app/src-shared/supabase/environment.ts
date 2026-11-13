export interface SupabaseBrowserEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string;
  readonly VITE_SUPABASE_ANON_KEY?: string;
}

export type SupabaseBrowserEnvironment =
  | { configured: true; url: string; key: string }
  | { configured: false; missing: readonly string[] };

export function readSupabaseBrowserEnvironment(
  env: SupabaseBrowserEnv,
): SupabaseBrowserEnvironment {
  const url = env.VITE_SUPABASE_URL?.trim() ?? "";
  const key =
    env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ||
    env.VITE_SUPABASE_ANON_KEY?.trim() ||
    "";

  if (url && key) return { configured: true, url, key };

  const missing: string[] = [];
  if (!url) missing.push("VITE_SUPABASE_URL");
  if (!key) {
    missing.push("VITE_SUPABASE_PUBLISHABLE_KEY / VITE_SUPABASE_ANON_KEY");
  }
  return { configured: false, missing };
}
