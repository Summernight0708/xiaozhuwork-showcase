// Local smoke server for the ai-task-breakdown Edge Function.
//
// Runs the Deno-free handler under Node so the full request path — JWT check
// against SUPABASE_URL, real model call, JSON parsing — can be verified with a
// real API key BEFORE deploying to the Edge Runtime. Not for production use.
//
// Usage:
//   1. cp supabase/functions/ai-task-breakdown/.env.local.example \
//        supabase/functions/ai-task-breakdown/.env.local
//   2. Fill in AI_API_KEY (and optionally AI_API_BASE_URL / AI_MODEL).
//   3. node scripts/serve-ai-breakdown-local.mjs
//   4. Log in on the production site, copy the Authorization bearer token of a
//      logged-in user from the browser network tab, then:
//        curl -s -X POST http://127.0.0.1:54323/ \
//          -H 'content-type: application/json' \
//          -H 'authorization: Bearer <token>' \
//          -d '{"prompt":"完成一份市场调研报告，包含问卷设计与数据分析。","taskCount":3}'

import { Buffer } from "node:buffer";
import { existsSync, readFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { handleAiTaskBreakdownRequest } from "../supabase/functions/ai-task-breakdown/handler.ts";

const PORT = 54323;
const here = dirname(fileURLToPath(import.meta.url));
const envFile = resolve(
  here,
  "../supabase/functions/ai-task-breakdown/.env.local",
);

function loadEnv() {
  const env = { ...process.env };
  if (existsSync(envFile)) {
    for (const line of readFileSync(envFile, "utf8").split("\n")) {
      const match = /^([A-Za-z0-9_]+)\s*=\s*(.*)$/.exec(line.trim());
      if (!match || env[match[1]]) continue;
      env[match[1]] = match[2].replace(/^["']|["']$/g, "");
    }
  }
  return env;
}

const env = loadEnv();
const config = {
  supabaseUrl: env.SUPABASE_URL || "https://xiaozhuwork.com",
  anonKey: env.SUPABASE_ANON_KEY || "",
  aiApiKey: env.AI_API_KEY || "",
  aiBaseUrl: env.AI_API_BASE_URL || "",
  aiModel: env.AI_MODEL || "",
};

if (!config.anonKey || !config.aiApiKey) {
  console.error(
    "Missing SUPABASE_ANON_KEY or AI_API_KEY. Fill .env.local first (see header of this file).",
  );
  process.exit(1);
}

const server = createServer(async (req, res) => {
  try {
    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }
    if (req.method !== "POST") {
      res.writeHead(405, { allow: "POST" });
      res.end();
      return;
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 20_000) {
        res.writeHead(413);
        res.end();
        return;
      }
      chunks.push(chunk);
    }
    const request = new globalThis.Request(`http://127.0.0.1:${PORT}/`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(req.headers.authorization
          ? { authorization: req.headers.authorization }
          : {}),
      },
      body: Buffer.concat(chunks).toString("utf8"),
    });
    const response = await handleAiTaskBreakdownRequest(request, { config });
    res.writeHead(
      response.status,
      Object.fromEntries(response.headers.entries()),
    );
    res.end(Buffer.from(await response.arrayBuffer()));
  } catch (error) {
    // Never log the request body or authorization header.
    console.error(
      "local smoke server error:",
      error instanceof Error ? error.name : "unknown",
    );
    res.writeHead(500);
    res.end();
  }
});

server.listen(PORT, "127.0.0.1", () => {
  const mask = (value) =>
    value ? `${value.slice(0, 6)}…${value.slice(-4)}` : "(missing)";
  console.log(
    `ai-task-breakdown local smoke server on http://127.0.0.1:${PORT}/`,
  );
  console.log(`  auth check -> ${config.supabaseUrl}`);
  console.log(
    `  model      -> ${config.aiModel || "qwen-plus (default)"} @ ${config.aiBaseUrl || "dashscope (default)"}`,
  );
  console.log(`  api key    -> ${mask(config.aiApiKey)}`);
});
