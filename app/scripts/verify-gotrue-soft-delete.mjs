/**
 * Disposable-only GoTrue Admin soft-delete acceptance.
 * The script never discovers credentials and refuses hosted/ordinary stacks.
 * It creates only a synthetic account; it never targets pre-existing users.
 */
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL, URL } from "node:url";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";

function disposableConfig(env) {
  const projectId = env.XIAOZHUWORK_AUTH_E2E_PROJECT_ID ?? "";
  if (!/^xiaozhuwork_f2_auth_e2e_[a-z0-9_-]{4,32}$/.test(projectId)) {
    throw new Error(
      "Refusing deletion E2E: dedicated disposable project ID required",
    );
  }
  if (
    env.XIAOZHUWORK_RUN_DISPOSABLE_AUTH_E2E !==
      "YES_DELETE_ONLY_NEW_SYNTHETIC_ACCOUNT" ||
    env.XIAOZHUWORK_AUTH_E2E_ACK_DISPOSABLE !== projectId
  ) {
    throw new Error(
      "Refusing deletion E2E: explicit disposable approval missing",
    );
  }
  const workdir = resolve(env.XIAOZHUWORK_AUTH_E2E_WORKDIR ?? "");
  const config = readFileSync(join(workdir, "supabase", "config.toml"), "utf8");
  if (
    !config.includes('project_id = "' + projectId + '"') ||
    !/\[api\]/.test(config) ||
    !/\[db\]/.test(config)
  ) {
    throw new Error(
      "Refusing deletion E2E: dedicated workdir identity mismatch",
    );
  }
  const apiPort = /\[api\]([^[]*)/
    .exec(config)?.[1]
    ?.match(/\bport\s*=\s*(\d+)/)?.[1];
  const dbPort = /\[db\]([^[]*)/
    .exec(config)?.[1]
    ?.match(/\bport\s*=\s*(\d+)/)?.[1];
  const api = new URL(env.XIAOZHUWORK_AUTH_E2E_API_URL ?? "");
  const db = new URL(env.XIAOZHUWORK_AUTH_E2E_DB_URL ?? "");
  if (
    api.protocol !== "http:" ||
    api.hostname !== "127.0.0.1" ||
    !api.port ||
    api.username ||
    api.password ||
    !["postgres:", "postgresql:"].includes(db.protocol) ||
    db.hostname !== "127.0.0.1" ||
    !db.port ||
    db.pathname !== "/postgres" ||
    api.port !== apiPort ||
    db.port !== dbPort
  ) {
    throw new Error(
      "Refusing deletion E2E: expected loopback test API and postgres DB",
    );
  }
  if (
    !env.XIAOZHUWORK_AUTH_E2E_ANON_KEY ||
    !env.XIAOZHUWORK_AUTH_E2E_SERVICE_ROLE_KEY
  ) {
    throw new Error(
      "Refusing deletion E2E: explicit test-only credentials required",
    );
  }
  return {
    apiUrl: api.origin,
    dbUrl: db.href,
    anonKey: env.XIAOZHUWORK_AUTH_E2E_ANON_KEY,
    serviceKey: env.XIAOZHUWORK_AUTH_E2E_SERVICE_ROLE_KEY,
  };
}

export async function verifyDisposableGoTrueSoftDelete(env = process.env) {
  const c = disposableConfig(env); // No network call before guard.
  const sql = postgres(c.dbUrl, { max: 1, connect_timeout: 5 });
  let userId = null;
  let deleted = false;
  try {
    const [database] = await sql.unsafe("select current_database() as name");
    assert.equal(database?.name, "postgres");
    const healthResponse = await globalThis.fetch(
      c.apiUrl + "/auth/v1/health",
      {
        signal: globalThis.AbortSignal.timeout(5000),
      },
    );
    assert.equal(healthResponse.status, 200);
    const health = await healthResponse.json();
    assert.match(health.version ?? "", /^v2\./);

    const admin = createClient(c.apiUrl, c.serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const member = createClient(c.apiUrl, c.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const email = "xiaozhuwork-soft-delete-" + randomUUID() + "@test.invalid";
    const password = randomBytes(30).toString("hex") + "aA!9";
    const created = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { nickname: "Disposable Secret Name" },
    });
    assert.ifError(created.error);
    userId = created.data.user?.id ?? null;
    assert.match(userId ?? "", /^[0-9a-f-]{36}$/i);

    const login = await member.auth.signInWithPassword({ email, password });
    assert.ifError(login.error);
    const refreshToken = login.data.session?.refresh_token;
    assert.ok(refreshToken, "test session refresh token must exist");
    const [before] = await sql.unsafe(
      "select email, deleted_at from auth.users where id = $1::uuid",
      [userId],
    );
    assert.equal(before?.email, email);
    assert.equal(before?.deleted_at, null);

    const response = await admin.auth.admin.deleteUser(userId, true);
    assert.ifError(response.error);
    deleted = true;

    const [after] = await sql.unsafe(
      "select email, phone, deleted_at, encrypted_password, " +
        "raw_user_meta_data, raw_app_meta_data from auth.users where id=$1::uuid",
      [userId],
    );
    assert.ok(after?.deleted_at);
    assert.match(after.email, /^[A-Za-z0-9_-]{43}$/);
    assert.match(after.phone, /^[A-Za-z0-9_-]{15}$/);
    assert.equal(after.encrypted_password, null);
    assert.deepEqual(after.raw_user_meta_data, {});
    assert.deepEqual(after.raw_app_meta_data, {});

    const identities = await sql.unsafe(
      "select provider_id, identity_data from auth.identities where user_id=$1::uuid",
      [userId],
    );
    assert.ok(identities.length > 0, "obfuscated identity rows should persist");
    for (const identity of identities) {
      assert.match(identity.provider_id, /^[A-Za-z0-9_-]{43}$/);
      assert.deepEqual(identity.identity_data, {});
    }
    const [sessions] = await sql.unsafe(
      "select count(*)::int as n from auth.sessions where user_id=$1::uuid",
      [userId],
    );
    assert.equal(sessions.n, 0, "Auth sessions should be revoked");

    const relogin = await createClient(c.apiUrl, c.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }).auth.signInWithPassword({ email, password });
    assert.ok(relogin.error, "soft-deleted account must not log in");
    const refreshed = await member.auth.refreshSession({
      refresh_token: refreshToken,
    });
    assert.ok(refreshed.error, "old refresh token must be refused");
    console.log(
      "PASS: disposable GoTrue " +
        health.version +
        " soft-delete; identities scrubbed, sessions closed, login/refresh denied",
    );
  } finally {
    if (userId && !deleted) {
      console.error("Synthetic test account was created but not soft-deleted.");
    }
    await sql.end({ timeout: 2 });
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  verifyDisposableGoTrueSoftDelete().catch((error) => {
    console.error("Disposable GoTrue E2E:", error.message);
    process.exitCode = 1;
  });
}
