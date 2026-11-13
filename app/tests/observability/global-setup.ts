import { build, preview } from "vite";

import {
  ensureLocalSupabase,
  localSupabase,
  waitForLocalSupabaseReady,
} from "../e2e/local-supabase";

export default async function observabilityGlobalSetup() {
  ensureLocalSupabase();
  await waitForLocalSupabaseReady();
  const local = localSupabase();

  process.env.VITE_SUPABASE_URL = local.apiUrl;
  process.env.VITE_SUPABASE_ANON_KEY = local.anonKey;
  process.env.VITE_UMAMI_HOST_URL = "https://analytics.test";
  process.env.VITE_UMAMI_WEBSITE_ID = "obs-e2e-site";
  process.env.VITE_SENTRY_DSN = "https://public@example.ingest.sentry.io/1";

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
