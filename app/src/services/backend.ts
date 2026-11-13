import type { SupabaseClient } from "@supabase/supabase-js";

import {
  createCommandAdapter,
  type CommandAdapter,
  type RpcPort,
} from "@/lib/command-adapter";
import {
  createSupabaseClient,
  validateSupabaseEnvironment,
} from "@/lib/supabase";
import type { Database } from "@/types/database.generated";

export interface XiaozhuWorkBackend {
  client: SupabaseClient<Database>;
  commands: CommandAdapter;
}

let backend: XiaozhuWorkBackend | null | undefined;

export function getBackend(): XiaozhuWorkBackend | null {
  if (backend !== undefined) return backend;

  const status = validateSupabaseEnvironment();
  if (!status.configured) {
    backend = null;
    return backend;
  }

  const client = createSupabaseClient();
  backend = {
    client,
    commands: createCommandAdapter(client as unknown as RpcPort),
  };
  return backend;
}

export function resetBackendForTests() {
  backend = undefined;
}
