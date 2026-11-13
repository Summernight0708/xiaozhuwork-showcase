import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

import { format } from "prettier";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(import.meta.url);
const executable = require.resolve("supabase/dist/supabase.js");

if (!existsSync(executable)) {
  throw new Error("Supabase CLI is missing. Run pnpm install first.");
}

const result = spawnSync(
  process.execPath,
  [
    executable,
    "gen",
    "types",
    "typescript",
    ...(process.env.SUPABASE_DB_URL
      ? ["--db-url", process.env.SUPABASE_DB_URL]
      : ["--local"]),
    "--schema",
    "public",
  ],
  { cwd: root, encoding: "utf8" },
);

if (result.status !== 0) {
  process.stderr.write(result.stderr);
  process.exit(result.status ?? 1);
}

const generated = await format(result.stdout, {
  parser: "typescript",
  endOfLine: "lf",
});
const target = join(root, "src", "types", "database.generated.ts");

if (process.argv.includes("--check")) {
  if (!existsSync(target) || readFileSync(target, "utf8") !== generated) {
    console.error("Generated database types are stale. Run pnpm db:types.");
    process.exit(1);
  }
  console.log("Generated database types are current.");
} else {
  writeFileSync(target, generated, "utf8");
  console.log(`Updated ${target}`);
}
