/* global process, fetch, console */
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { execSync } from "node:child_process";
import { URL } from "node:url";

import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";

function readLocalSupabaseState() {
  const output = execSync("corepack pnpm exec supabase status --output json", {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
    windowsHide: true,
  });
  return JSON.parse(output);
}
const localState = readLocalSupabaseState();
const apiUrl = localState.API_URL;
const anonKey = localState.PUBLISHABLE_KEY ?? localState.ANON_KEY;
const serviceKey = localState.SERVICE_ROLE_KEY;
const dbUrl = localState.DB_URL;
const origin = "http://127.0.0.1:5174";
function localOnly(value, expectedProtocol) {
  if (!value) return false;
  try {
    const parsed = new URL(value);
    return (
      parsed.protocol === expectedProtocol &&
      ["127.0.0.1", "localhost"].includes(parsed.hostname)
    );
  } catch {
    return false;
  }
}

if (
  process.env.OPS_HTTP_TEST_ALLOW_LOCAL !== "1" ||
  !localOnly(apiUrl, "http:") ||
  !localOnly(dbUrl, "postgresql:") ||
  !anonKey ||
  !serviceKey
) {
  throw new Error(
    "Refusing Ops HTTP integration outside an explicitly enabled local sandbox",
  );
}

const db = postgres(dbUrl, { max: 2, ssl: false });
const admin = createClient(apiUrl, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const createdUserIds = [];
const password = `Ops-local-${randomUUID()}!`;

async function createUser(label) {
  const email = `ops-${label}-${randomUUID()}@example.test`;
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  assert.equal(error, null, `create ${label} local Auth user`);
  assert.ok(data.user?.id);
  createdUserIds.push(data.user.id);
  return { id: data.user.id, email };
}

async function signIn(user) {
  const client = createClient(apiUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email: user.email,
    password,
  });
  assert.equal(error, null, `sign in ${user.email}`);
  assert.ok(data.session?.access_token);
  return data.session.access_token;
}

async function call(token, body, requestOrigin = origin) {
  const headers = {
    apikey: anonKey,
    origin: requestOrigin,
    "content-type": "application/json",
  };
  if (token) headers.authorization = `Bearer ${token}`;
  const response = await fetch(`${apiUrl}/functions/v1/ops-api`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    cache: "no-store",
  });
  let payload = null;
  try {
    payload = await response.json();
  } catch {
    // JWT gateway errors need not use the function JSON envelope.
  }
  return { response, payload };
}

try {
  const enabled = await createUser("enabled");
  const disabled = await createUser("disabled");
  const normal = await createUser("normal");
  const target = await createUser("target");

  await db`
    insert into private.ops_admins(user_id,enabled,created_by)
    values
      (${enabled.id}::uuid,true,${enabled.id}::uuid),
      (${disabled.id}::uuid,false,${enabled.id}::uuid)
  `;

  const enabledToken = await signIn(enabled);
  const disabledToken = await signIn(disabled);
  const normalToken = await signIn(normal);

  const { data: directAccess, error: directAccessError } = await admin.rpc(
    "ops_assert_access_service",
    { p_operator_user_id: normal.id },
  );
  assert.equal(
    directAccessError,
    null,
    "service-role client can call ops access assertion",
  );
  assert.deepEqual(
    directAccess,
    { ok: false, code: "FORBIDDEN" },
    "service RPC returns forbidden for a normal user",
  );

  const unauthenticated = await call(null, { action: "access" });
  assert.equal(
    unauthenticated.response.status,
    401,
    "missing bearer is rejected by Edge JWT verification",
  );

  const normalResult = await call(normalToken, { action: "access" });
  assert.equal(normalResult.response.status, 403);
  assert.deepEqual(normalResult.payload, { ok: false, code: "FORBIDDEN" });

  const disabledResult = await call(disabledToken, { action: "access" });
  assert.equal(disabledResult.response.status, 403);
  assert.deepEqual(disabledResult.payload, { ok: false, code: "FORBIDDEN" });

  const enabledResult = await call(enabledToken, { action: "access" });
  assert.equal(
    enabledResult.response.status,
    200,
    JSON.stringify(enabledResult.payload),
  );
  assert.equal(enabledResult.payload?.ok, true);
  assert.equal(enabledResult.payload?.data?.userId, enabled.id);
  const allowedCors = enabledResult.response.headers.get(
    "access-control-allow-origin",
  );
  assert.ok(
    allowedCors === origin || allowedCors === "*",
    `local Edge gateway returned unexpected CORS header: ${allowedCors}`,
  );
  const hostileOrigin = await call(
    enabledToken,
    { action: "access" },
    "https://evil.example",
  );
  assert.equal(hostileOrigin.response.status, 403);
  // Local Supabase gateway may append wildcard CORS after the function response.
  // The application-level security property is that a hostile Origin never
  // receives successful Ops data; exact handler headers are covered in unit tests.
  const requestId = randomUUID();
  const lookup = await call(enabledToken, {
    action: "account.lookup",
    query: target.email,
    requestId,
  });
  assert.equal(lookup.response.status, 200, JSON.stringify(lookup.payload));
  assert.equal(lookup.payload?.ok, true);
  assert.equal(lookup.payload?.data?.schemaVersion, 1);
  assert.equal(lookup.payload?.data?.userId, target.id);
  assert.equal(lookup.payload?.data?.email, target.email);
  const serialized = JSON.stringify(lookup.payload);
  for (const forbidden of [
    "taskTitle",
    "projectName",
    "fileName",
    "body",
    "notificationText",
  ]) {
    assert.equal(
      serialized.includes(forbidden),
      false,
      `${forbidden} must not escape L1`,
    );
  }

  const audits = await db`
    select operator_user_id,target_user_id,action,request_id
    from private.ops_access_audit
    where request_id=${requestId}::uuid
  `;
  assert.equal(audits.length, 1, "one successful lookup creates one audit row");
  assert.equal(audits[0].operator_user_id, enabled.id);
  assert.equal(audits[0].target_user_id, target.id);
  assert.equal(audits[0].action, "account_support_view");

  console.log(
    "PASS ops-api real HTTP: unauth=401 normal=403 disabled=403 enabled=200 auditedLookup=1 hostileOrigin=403",
  );
} finally {
  for (const id of createdUserIds.reverse()) {
    try {
      await admin.auth.admin.deleteUser(id);
    } catch {
      // The disposable database is reset after this gate; never hide test failure.
    }
  }
  await db.end({ timeout: 5 });
}
