// Reproducible isolated D test harness. No shared DB URL, reset, hosted API or volume mount.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import process from "node:process";
import console from "node:console";
import { setTimeout } from "node:timers";

const docker = process.env.DOCKER_EXE || "docker";
const container = "xiaozhuwork-d-external-evidence-test";
const storageContainer = "xiaozhuwork-d-external-evidence-storage-bootstrap";
const cache = resolve("node_modules/.cache/external-evidence-validation");
mkdirSync(cache, { recursive: true });
const password = "external-evidence-isolated-only";
const dbUrl = `postgresql://postgres:${password}@127.0.0.1:55444/postgres`;
const dockerCall = (args, options = {}) =>
  execFileSync(docker, args, {
    encoding: "utf8",
    timeout: 60000,
    maxBuffer: 16 * 1024 * 1024,
    ...options,
  });
const sql = (input, user = "postgres", storage = false) =>
  dockerCall(
    [
      "exec",
      "-i",
      ...(storage
        ? [
            "-e",
            "PGOPTIONS=-c search_path=storage,public,extensions -c storage.install_roles=false",
          ]
        : []),
      container,
      "psql",
      "-U",
      user,
      "-d",
      "postgres",
      "-X",
      "-q",
      "-A",
      "-t",
      "-v",
      "ON_ERROR_STOP=1",
    ],
    { input },
  );
function stopOwnedContainer() {
  const label = dockerCall([
    "inspect",
    "--format",
    '{{index .Config.Labels "xiaozhuwork.workstream"}}',
    container,
  ]).trim();
  if (label !== "D-external-evidence-test")
    throw new Error("Refusing cleanup: container label mismatch");
  dockerCall(["stop", container]);
}
let created = false;
let storageCreated = false;
try {
  // Docker fails on a name/port collision. Never stop or reset someone else's container.
  dockerCall([
    "run",
    "--detach",
    "--rm",
    "--name",
    container,
    "--label",
    "xiaozhuwork.workstream=D-external-evidence-test",
    "--memory",
    "768m",
    "--cpus",
    "1",
    "--pids-limit",
    "256",
    "--publish",
    "127.0.0.1:55444:5432",
    "--env",
    `POSTGRES_PASSWORD=${password}`,
    "--env",
    "POSTGRES_DB=postgres",
    "public.ecr.aws/supabase/postgres:17.6.1.171",
  ]);
  created = true;
  for (let n = 0; n < 60; n++) {
    try {
      dockerCall(
        ["exec", container, "pg_isready", "-h", "127.0.0.1", "-p", "5432"],
        { stdio: "ignore" },
      );
      break;
    } catch (error) {
      if (n === 59) throw error;
      await new Promise((r) => setTimeout(r, 500));
    }
  }
  dockerCall([
    "create",
    "--name",
    storageContainer,
    "--network",
    "none",
    "--entrypoint",
    "sh",
    "public.ecr.aws/supabase/storage-api:v1.77.5",
  ]);
  storageCreated = true;
  const storagePath = resolve(cache, "storage");
  mkdirSync(storagePath, { recursive: true });
  dockerCall([
    "cp",
    `${storageContainer}:/app/migrations/tenant/.`,
    storagePath,
  ]);
  for (const name of readdirSync(storagePath)
    .filter((n) => n.endsWith(".sql"))
    .sort((a, b) => parseInt(a) - parseInt(b))) {
    sql(
      readFileSync(resolve(storagePath, name), "utf8"),
      "supabase_admin",
      true,
    );
  }
  console.log("Official Storage bootstrap complete");
  const migrations = readdirSync("supabase/migrations")
    .filter((name) => name.endsWith(".sql"))
    .sort();
  sql(
    "create schema external_evidence_test; revoke all on schema external_evidence_test from public; create table external_evidence_test.migrations(name text primary key,sha256 text not null);",
  );
  for (const name of migrations) {
    const source = readFileSync(`supabase/migrations/${name}`);
    sql(`begin;\n${source.toString("utf8")}\ncommit;`);
    const sha = createHash("sha256").update(source).digest("hex");
    if (!/^[\da-z_]+\.sql$/.test(name))
      throw new Error("Unexpected migration filename");
    sql(
      `insert into external_evidence_test.migrations values ('${name}','${sha}');`,
    );
  }
  console.log(
    `Clean replay: ${migrations.length} migrations; exact SHA-256 manifest recorded`,
  );
  const testFiles = process.argv.includes("--all-pgtap")
    ? readdirSync("supabase/tests/database")
        .filter((name) => name.endsWith(".test.sql"))
        .sort()
    : ["external_evidence.test.sql"];
  const failures = [];
  let checks = 0;
  for (const name of testFiles) {
    try {
      const output = sql(
        readFileSync(`supabase/tests/database/${name}`, "utf8"),
      );
      writeFileSync(resolve(cache, `${name}.log`), output);
      checks += (output.match(/^ok \d+/gm) ?? []).length;
      if (
        /^not ok\b|Looks like you failed|No tests run!/m.test(output) ||
        !/^1\.\.\d+/m.test(output)
      )
        failures.push(name);
    } catch (error) {
      failures.push(name);
      writeFileSync(
        resolve(cache, `${name}.log`),
        String(error.stdout ?? "") + String(error.stderr ?? error),
      );
    }
  }
  console.log(
    `pgTAP: ${testFiles.length} files, ${checks} passing assertions, failures: ${failures.join(", ") || "none"}`,
  );
  execFileSync(
    process.execPath,
    [
      "node_modules/vitest/vitest.mjs",
      "run",
      "--config",
      "vitest.db.config.ts",
      "tests/database/external-evidence-concurrency.spec.ts",
    ],
    {
      stdio: "inherit",
      timeout: 180000,
      env: { ...process.env, XIAOZHUWORK_D_DB_URL: dbUrl, TEMP: cache, TMP: cache },
    },
  );
  if (failures.length)
    throw new Error(`pgTAP failures: ${failures.join(", ")}; see ${cache}`);
} finally {
  if (storageCreated) dockerCall(["rm", storageContainer]);
  if (created) {
    stopOwnedContainer(); // --rm removes only this invocation's disposable container.
  }
}
