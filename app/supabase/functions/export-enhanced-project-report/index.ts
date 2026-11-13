import { handleEnhancedReportRequest } from "../_shared/enhanced-report-edge.ts";

Deno.serve((request: Request) =>
  handleEnhancedReportRequest(request, {
    supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
    anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  }),
);
