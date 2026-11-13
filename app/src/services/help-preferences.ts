import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.generated";

export const HELP_HINT_KEYS = [
  "v1:intro:leader",
  "v1:intro:admin",
  "v1:intro:member",
  "v1:intro:observer",
  "v1:hint:dependencies",
  "v1:hint:submission",
  "v1:hint:review",
  "v1:hint:file-rollback",
  "v1:hint:advanced-permissions",
] as const;

export type HelpHintKey = (typeof HELP_HINT_KEYS)[number];

export async function listHelpDismissals(
  client: SupabaseClient<Database>,
  userId: string,
): Promise<string[]> {
  const { data, error } = await client
    .from("user_help_dismissals")
    .select("hint_key")
    .eq("user_id", userId);
  if (error) throw error;
  return (data ?? []).map((row) => row.hint_key);
}

export async function saveHelpDismissal(
  client: SupabaseClient<Database>,
  userId: string,
  key: HelpHintKey,
): Promise<void> {
  const { error } = await client
    .from("user_help_dismissals")
    .upsert(
      { user_id: userId, hint_key: key },
      { onConflict: "user_id,hint_key", ignoreDuplicates: true },
    );
  if (error) throw error;
}
