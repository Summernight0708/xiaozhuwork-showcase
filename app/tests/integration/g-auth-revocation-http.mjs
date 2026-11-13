/* global process, fetch, console */
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";

const apiUrl = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const schedulerSecret = process.env.LIFECYCLE_SCHEDULER_SECRET;
const dbUrl = process.env.SUPABASE_DB_URL;
if (
  apiUrl !== "http://127.0.0.1:55811" ||
  !serviceKey ||
  !schedulerSecret ||
  schedulerSecret.length < 32 ||
  !/^postgresql:\/\/postgres:postgres@127\.0\.0\.1:55812\/postgres/.test(
    dbUrl ?? "",
  )
) {
  throw new Error("Isolated G Auth HTTP test environment was not confirmed");
}
const db = postgres(dbUrl, { max: 2, ssl: false });
const admin = createClient(apiUrl, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const email = `g-revocation-${randomUUID()}@example.test`;
const password = `G-verified-${randomUUID()}!`;
try {
  const { data: created, error: createError } =
    await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
  assert.equal(
    createError,
    null,
    "only a disposable local user must be created",
  );
  const uid = created.user?.id;
  assert.ok(uid, "GoTrue returned the disposable user's UUID");

  const client = createClient(apiUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: signed, error: signError } =
    await client.auth.signInWithPassword({ email, password });
  assert.equal(
    signError,
    null,
    "disposable account can sign in before revocation",
  );
  assert.ok(signed.session?.refresh_token);

  const before = await db`
    select count(*)::int as sessions
    from auth.sessions where user_id=${uid}::uuid
  `;
  assert.ok(before[0].sessions > 0, "real GoTrue session was created");

  // A still-valid JWT must lose project access immediately through the
  // lifecycle RLS fence even before GoTrue JWT expiration.
  const ownerId = randomUUID();
  await db`insert into auth.users(id,email) values (
    ${ownerId}::uuid,${`g-owner-${ownerId}@example.test`}
  )`;
  const [project] = await db`
    insert into public.projects(name,deadline_at,created_by,leader_id)
    values ('G revocation JWT fence',now()+interval '8 days',
      ${ownerId}::uuid,${ownerId}::uuid)
    returning id
  `;
  await db`
    insert into public.project_members(project_id,user_id,role,member_state)
    values(${project.id}::uuid,${ownerId}::uuid,'leader','active'),
          (${project.id}::uuid,${uid}::uuid,'member','active')
  `;
  const initialAccess = await client
    .from("projects")
    .select("id")
    .eq("id", project.id);
  assert.equal(initialAccess.error, null);
  assert.equal(
    initialAccess.data?.length,
    1,
    "JWT sees member project before request",
  );

  const generation = 1;
  await db`insert into public.account_lifecycle_requests(
    user_id,state,generation,version,requested_at,cancel_until
  ) values(
    ${uid}::uuid,'pending',${generation},1,
    now()-interval '40 days',now()-interval '10 days'
  )`;

  const blockedAccess = await client
    .from("projects")
    .select("id")
    .eq("id", project.id);
  assert.equal(blockedAccess.error, null);
  assert.equal(
    blockedAccess.data?.length,
    0,
    "previously valid JWT cannot read shared project after lifecycle request",
  );

  const response = await fetch(`${apiUrl}/functions/v1/lifecycle-worker`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${serviceKey}`,
      apikey: serviceKey,
      "x-lifecycle-scheduler-secret": schedulerSecret,
      "content-type": "application/json",
    },
    body: "{}",
  });
  const result = await response.json();
  assert.equal(response.status, 200, JSON.stringify(result));
  assert.equal(result.ok, true);
  assert.ok(
    result.sessionsRevoked >= 1,
    "trusted worker revoked an expired account",
  );

  const state = await db`
    select r.state,r.auth_revoked_at,u.banned_until
      from public.account_lifecycle_requests r join auth.users u on u.id=r.user_id
    where r.user_id=${uid}::uuid
  `;
  assert.equal(
    state[0].state,
    "blocked",
    "redaction stays blocked / never completed",
  );
  assert.ok(state[0].auth_revoked_at, "real Auth revocation checkpoint exists");
  assert.ok(
    new Date(state[0].banned_until).getTime() > Date.now() + 300 * 86400 * 1000,
  );

  const sessions = await db`
    select count(*)::int as remaining from auth.sessions where user_id=${uid}::uuid
  `;
  const refreshRows = await db`
    select count(*)::int as remaining from auth.refresh_tokens where user_id=${uid}::text
  `;
  assert.equal(sessions[0].remaining, 0, "real sessions were revoked");
  assert.equal(
    refreshRows[0].remaining,
    0,
    "real refresh credentials were revoked",
  );

  const { error: refreshError } = await client.auth.refreshSession({
    refresh_token: signed.session.refresh_token,
  });
  assert.ok(
    refreshError,
    "the previously valid refresh token must fail against GoTrue",
  );

  console.log(
    "PASS isolated real Auth: login→expired lifecycle→admin ban→sessions=0→refresh denied; account stays blocked",
  );
} finally {
  await db.end({ timeout: 5 });
}
