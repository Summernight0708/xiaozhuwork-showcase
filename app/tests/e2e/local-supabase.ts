import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve, join } from "node:path";
import type { Page } from "@playwright/test";
import postgres from "postgres";

export interface LocalSupabaseEnvironment {
  apiUrl: string;
  anonKey: string;
  dbUrl: string;
  mailpitUrl: string;
}

function command() {
  return process.platform === "win32"
    ? (process.env.ComSpec ?? "cmd.exe")
    : "corepack";
}

function commandArgs(args: string[]) {
  return process.platform === "win32"
    ? ["/d", "/s", "/c", "corepack", ...args]
    : args;
}

export function runCorepack(args: string[], stdio: "ignore" | "pipe" = "pipe") {
  return execFileSync(command(), commandArgs(args), {
    cwd: process.cwd(),
    encoding: "utf8",
    stdio,
  });
}

// A dedicated G database must be explicitly selected before any E2E reset.
function isolatedSupabaseWorkdir(): string | null {
  const raw = process.env.XIAOZHUWORK_E2E_SUPABASE_WORKDIR;
  if (!raw) return null;
  const root = resolve(raw);
  const config = readFileSync(join(root, "supabase", "config.toml"), "utf8");
  const knownG =
    /^project_id\s*=\s*"xiaozhuwork_g_isolated_20261010"/m.test(config) &&
    /^port\s*=\s*55812\s*$/m.test(config);
  const ownedF2 =
    root === resolve("test-results/f2-validation") &&
    /^project_id\s*=\s*"xiaozhuwork_f2_final_9d28fff2"/m.test(config) &&
    /^port\s*=\s*56122\s*$/m.test(config) &&
    /^port\s*=\s*56121\s*$/m.test(config);
  const ownedUiReview =
    root === resolve("../xiaozhuwork-ui-visual-validation") &&
    /^project_id\s*=\s*"xiaozhuwork_ui_review_20261013"/m.test(config) &&
    /^port\s*=\s*56922\s*$/m.test(config) &&
    /^port\s*=\s*56921\s*$/m.test(config);
  if (!knownG && !ownedF2 && !ownedUiReview) {
    throw new Error(
      "Refusing E2E reset: expected verified disposable G, worktree-owned F2 or exact UI-review stack",
    );
  }
  return root;
}
function runIsolatedSupabase(
  args: string[],
  stdio: "ignore" | "pipe" = "pipe",
) {
  const root = isolatedSupabaseWorkdir();
  if (!root) throw new Error("Isolated E2E Supabase target missing");
  return runCorepack(
    ["pnpm", "exec", "supabase", ...args, "--workdir", root],
    stdio,
  );
}
function sleepSync(ms: number) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function localProjectId() {
  const root = isolatedSupabaseWorkdir();
  const config = readFileSync(
    join(root ?? ".", "supabase", "config.toml"),
    "utf8",
  );
  const match = /^project_id\s*=\s*"([^"]+)"/m.exec(config);
  if (!match?.[1]) throw new Error("Supabase project_id is missing");
  return match[1];
}

function repairResetDependentServices() {
  const projectId = localProjectId();
  // `supabase db reset` recreates the database while GoTrue keeps running.
  // Restart Auth so its own schema migrations are applied to the fresh DB,
  // and start Edge Runtime in case a previous local run left it stopped.
  execFileSync("docker", ["restart", `supabase_auth_${projectId}`], {
    cwd: process.cwd(),
    stdio: "ignore",
  });
  // Supabase CLI can remove the isolated Edge container when a standalone
  // `supabase functions serve` is used. REST-only E2E suites do not need
  // that container; service-level E2E must launch a verified Edge runtime.
  try {
    execFileSync("docker", ["start", `supabase_edge_runtime_${projectId}`], {
      cwd: process.cwd(),
      stdio: "ignore",
    });
  } catch (error) {
    if (isolatedSupabaseWorkdir()) return;
    // A preceding standalone `supabase functions serve` can remove the Edge
    // container entirely. A plain `docker start` cannot recreate it.
    // Restore the owned local stack, preserving its database volume.
    runCorepack(["pnpm", "db:stop"], "ignore");
    runCorepack(["pnpm", "db:start"], "ignore");
    const running = execFileSync(
      "docker",
      [
        "inspect",
        "--format",
        "{{.State.Running}}",
        `supabase_edge_runtime_${projectId}`,
      ],
      {
        cwd: process.cwd(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      },
    ).trim();
    if (running !== "true") throw error;
  }
}

function runCorepackWithRetry(
  args: string[],
  attempts = 3,
  stdio: "ignore" | "pipe" = "pipe",
) {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return runCorepack(args, stdio);
    } catch (error) {
      lastError = error;
      if (attempt + 1 < attempts) sleepSync(500 * (attempt + 1));
    }
  }
  throw lastError;
}

export function ensureLocalSupabase() {
  if (isolatedSupabaseWorkdir()) {
    try {
      runIsolatedSupabase(["status"], "ignore");
    } catch {
      runIsolatedSupabase(["start", "--yes"], "ignore");
    }
    runIsolatedSupabase(["db", "reset", "--local", "--no-seed"], "ignore");
    repairResetDependentServices();
    return;
  }
  try {
    runCorepack(["pnpm", "db:status"], "ignore");
  } catch {
    runCorepackWithRetry(["pnpm", "db:start"]);
  }
  // Docker can briefly report the recreated database container as "starting"
  // while Supabase CLI is rebuilding schema. Retry the whole local reset a
  // bounded number of times; deterministic migration errors still fail all
  // attempts and surface to Playwright.
  runCorepackWithRetry(["pnpm", "db:reset"]);
  repairResetDependentServices();
}

async function authSchemaReady(dbUrl: string) {
  const sql = postgres(dbUrl, {
    max: 1,
    connect_timeout: 2,
    idle_timeout: 1,
  });

  try {
    const rows = await sql`
      select exists (
        select 1
        from information_schema.columns
        where table_schema = 'auth'
          and table_name = 'users'
          and column_name = 'banned_until'
      ) as ready
    `;
    return rows[0]?.ready === true;
  } catch {
    return false;
  } finally {
    await sql.end({ timeout: 1 });
  }
}

export async function waitForLocalSupabaseReady(timeoutMs = 20_000) {
  const { apiUrl, anonKey, dbUrl, mailpitUrl } = localSupabase();
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const [auth, rest, mail, authSchema] = await Promise.all([
        fetch(`${apiUrl}/auth/v1/health`),
        fetch(`${apiUrl}/rest/v1/`, {
          headers: { apikey: anonKey },
        }),
        fetch(`${mailpitUrl}/api/v1/messages`),
        authSchemaReady(dbUrl),
      ]);
      if (auth.ok && rest.ok && mail.ok && authSchema) return;
    } catch {
      // db reset can return just before dependent containers finish restarting.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Local Supabase did not become ready after reset");
}

function localStatusEnv() {
  const isolated = isolatedSupabaseWorkdir();
  let lastError: unknown;
  for (let attempt = 0; attempt < 20; attempt += 1) {
    try {
      const stdout = isolated
        ? runIsolatedSupabase(["status", "-o", "env"])
        : runCorepack(["pnpm", "exec", "supabase", "status", "-o", "env"]);
      const complete =
        /^API_URL=/m.test(stdout) &&
        /^ANON_KEY=/m.test(stdout) &&
        /^DB_URL=/m.test(stdout) &&
        /^(?:MAILPIT_URL|INBUCKET_URL)=/m.test(stdout);
      if (complete) return stdout;
      lastError = new Error("Local Supabase status output is incomplete");
    } catch (error) {
      lastError = error;
    }
    if (attempt < 19) sleepSync(250);
  }
  throw lastError;
}

export function localSupabase(): LocalSupabaseEnvironment {
  let lastIncompleteStatus = "";
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const stdout = localStatusEnv();
    const values = new Map<string, string>();

    for (const line of stdout.split(/\r?\n/)) {
      const match = /^([A-Z0-9_]+)="(.*)"$/.exec(line.trim());
      if (match) values.set(match[1]!, match[2]!);
    }

    const apiUrl = values.get("API_URL");
    const anonKey = values.get("ANON_KEY");
    const dbUrl = values.get("DB_URL");
    const mailpitUrl = values.get("MAILPIT_URL") ?? values.get("INBUCKET_URL");
    if (apiUrl && anonKey && dbUrl && mailpitUrl) {
      return { apiUrl, anonKey, dbUrl, mailpitUrl };
    }

    lastIncompleteStatus = stdout;
    if (attempt < 19) sleepSync(250);
  }

  throw new Error(
    `Local Supabase status did not expose E2E values after retries: ${lastIncompleteStatus
      .split(/\r?\n/)
      .filter((line) => /^[A-Z0-9_]+=/.test(line.trim()))
      .map((line) => line.split("=")[0])
      .join(",")}`,
  );
}

function recipientAddresses(message: Record<string, unknown>) {
  const raw = (message.To ?? message.to ?? []) as unknown;
  if (!Array.isArray(raw)) return [];

  return raw.flatMap((recipient) => {
    if (typeof recipient === "string") return [recipient];
    if (!recipient || typeof recipient !== "object") return [];

    const record = recipient as Record<string, unknown>;
    const address =
      record.Address ?? record.address ?? record.Email ?? record.email;
    return typeof address === "string" ? [address] : [];
  });
}

export const E2E_PASSWORD = "XiaozhuWork-e2e-password-1";

export async function findAuthUsersByEmail(email: string) {
  const { dbUrl } = localSupabase();
  const sql = postgres(dbUrl, {
    max: 1,
    connect_timeout: 2,
    idle_timeout: 1,
  });
  try {
    const rows = await sql<
      Array<{ id: string; email: string | null; created_at: string }>
    >`
      select id::text, email, created_at::text
      from auth.users
      where lower(email) = lower(${email})
      order by created_at asc
    `;
    return rows;
  } finally {
    await sql.end({ timeout: 1 });
  }
}

export async function registerWithPassword(
  page: Page,
  email: string,
  password = E2E_PASSWORD,
  timeoutMs = 20_000,
) {
  await page.goto("/register");
  await page.locator('input[type="email"]').fill(email);

  const otpResponse = page.waitForResponse(
    (response) =>
      response.url().includes("/auth/v1/otp") &&
      response.request().method() === "POST",
    { timeout: 15_000 },
  );
  await page.getByRole("button", { name: "获取验证码" }).click();
  const response = await otpResponse;
  if (response.status() !== 200) {
    throw new Error(`Signup OTP request failed with HTTP ${response.status()}`);
  }

  const otp = await waitForOtp(email, timeoutMs);
  await page.locator("#otp-code").fill(otp);
  const verifyResponse = page.waitForResponse(
    (candidate) =>
      candidate.url().includes("/auth/v1/verify") &&
      candidate.request().method() === "POST",
    { timeout: 15_000 },
  );
  await page.getByRole("button", { name: "验证邮箱" }).click();
  const verified = await verifyResponse;
  if (verified.status() !== 200) {
    throw new Error(
      `Signup OTP verification failed with HTTP ${verified.status()}`,
    );
  }

  const passwordInputs = page.locator('input[autocomplete="new-password"]');
  await passwordInputs.nth(0).waitFor({ state: "visible" });
  await passwordInputs.nth(0).fill(password);
  await passwordInputs.nth(1).fill(password);

  const passwordResponse = page.waitForResponse(
    (candidate) =>
      candidate.url().includes("/auth/v1/user") &&
      ["PUT", "PATCH"].includes(candidate.request().method()),
    { timeout: 15_000 },
  );
  await page.getByRole("button", { name: "完成注册" }).click();
  const updated = await passwordResponse;
  if (!updated.ok()) {
    throw new Error(`Password setup failed with HTTP ${updated.status()}`);
  }
  await page.waitForURL(/\/(?:projects|account\/settings)(?:$|[/?#])/, {
    timeout: 15_000,
  });
}

export async function loginWithPassword(
  page: Page,
  email: string,
  password = E2E_PASSWORD,
) {
  await page.goto("/login");
  await page.locator('input[type="email"]').fill(email);
  await page.locator('input[type="password"]').fill(password);

  const loginResponse = page.waitForResponse(
    (response) =>
      response.url().includes("/auth/v1/token") &&
      response.request().method() === "POST",
    { timeout: 15_000 },
  );
  await page.getByRole("button", { name: "登录", exact: true }).click();
  const response = await loginResponse;
  if (!response.ok()) {
    throw new Error(`Password login failed with HTTP ${response.status()}`);
  }
  await page.waitForURL(/\/(?:projects|account\/settings)(?:$|[/?#])/, {
    timeout: 15_000,
  });
}

export async function waitForOtp(email: string, timeoutMs = 20_000) {
  const { mailpitUrl } = localSupabase();
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const listResponse = await fetch(`${mailpitUrl}/api/v1/messages`);
    if (listResponse.ok) {
      const list = (await listResponse.json()) as {
        messages?: Array<Record<string, unknown>>;
      };
      const match = (list.messages ?? [])
        .filter((message) =>
          recipientAddresses(message).some(
            (address) => address.toLowerCase() === email.toLowerCase(),
          ),
        )
        .sort((left, right) => {
          const leftAt = Date.parse(String(left.Created ?? left.created ?? ""));
          const rightAt = Date.parse(
            String(right.Created ?? right.created ?? ""),
          );
          if (!Number.isFinite(leftAt) || !Number.isFinite(rightAt)) return 0;
          return rightAt - leftAt;
        })[0];
      const id = match?.ID ?? match?.id;

      if (typeof id === "string") {
        const messageResponse = await fetch(
          `${mailpitUrl}/api/v1/message/${encodeURIComponent(id)}`,
        );
        if (messageResponse.ok) {
          const message = (await messageResponse.json()) as Record<
            string,
            unknown
          >;
          const source = [
            message.Text,
            message.text,
            message.HTML,
            message.html,
            message.Subject,
            message.subject,
          ]
            .filter((part): part is string => typeof part === "string")
            .join("\n");
          const contextual = /(?:code|token|otp)[^0-9]{0,100}([0-9]{6})/i.exec(
            source,
          )?.[1];
          const fallback = /\b([0-9]{6})\b/.exec(source)?.[1];

          if (contextual || fallback) return contextual ?? fallback!;
        }
      }
    }

    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  throw new Error(`Timed out waiting for OTP email for ${email}`);
}
