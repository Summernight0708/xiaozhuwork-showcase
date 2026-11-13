import { createClient } from "npm:@supabase/supabase-js@2";
import {
  handleAnalyticsRollupRequest,
  type AnalyticsRollupInput,
} from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const serviceCredential = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve((request: Request) =>
  handleAnalyticsRollupRequest(request, {
    serviceCredential,
    now: () => new Date(),
    runRollup: async (input: AnalyticsRollupInput) => {
      if (!url || !serviceCredential) {
        return { ok: false, code: "WORKER_NOT_CONFIGURED" };
      }

      const client = createClient(url, serviceCredential, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await client.rpc(
        "run_analytics_daily_rollup_service",
        {
          p_from_date: input.fromDate,
          p_to_date: input.toDate,
          p_definition_version: input.definitionVersion,
        },
      );

      if (error) {
        console.error("Analytics rollup RPC failed", error.code);
        return { ok: false, code: "ROLLUP_FAILED" };
      }

      const result = data as { ok?: boolean; code?: string } | null;
      if (!result || result.ok !== true) {
        return {
          ok: false,
          code: result?.code ?? "ROLLUP_FAILED",
        };
      }

      return { ok: true, data: (result as { data?: unknown }).data ?? null };
    },
  }),
);
