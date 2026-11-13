import { handleAiTaskBreakdownRequest } from "./handler.ts";

Deno.serve((request) =>
  handleAiTaskBreakdownRequest(request, {
    config: {
      supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
      anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      aiApiKey: Deno.env.get("AI_API_KEY") ?? "",
      aiBaseUrl:
        Deno.env.get("AI_API_BASE_URL") ??
        "https://dashscope.aliyuncs.com/compatible-mode/v1",
      aiModel: Deno.env.get("AI_MODEL") ?? "qwen-plus",
    },
  }),
);
