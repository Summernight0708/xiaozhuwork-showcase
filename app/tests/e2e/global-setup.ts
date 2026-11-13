import { build, preview } from "vite";

import {
  ensureLocalSupabase,
  localSupabase,
  waitForLocalSupabaseReady,
} from "./local-supabase";

export default async function globalSetup() {
  ensureLocalSupabase();
  await waitForLocalSupabaseReady();
  const local = localSupabase();
  process.env.VITE_SUPABASE_URL = local.apiUrl;
  process.env.VITE_SUPABASE_ANON_KEY = local.anonKey;
  await build();

  const server = await preview({
    preview: {
      host: "127.0.0.1",
      port: 4173,
      strictPort: true,
    },
  });

  return async () => {
    await server.close();
  };
}
