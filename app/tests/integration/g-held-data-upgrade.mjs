/* global process, console, fetch, TextEncoder */
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";

const phase = process.argv[2];
if (phase !== "before" && phase !== "after") {
  throw new Error("Specify before or after");
}
const dbUrl = process.env.SUPABASE_DB_URL;
const apiUrl = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const artifact = process.env.G_UPGRADE_FIXTURE_PATH;
const baselineMigrations = Number(
  process.env.G_UPGRADE_BASELINE_MIGRATIONS ?? "51",
);
if (![50, 51].includes(baselineMigrations)) {
  throw new Error(
    "Only exact 50- or 51-migration G upgrade rehearsals are permitted",
  );
}
if (
  apiUrl !== "http://127.0.0.1:55911" ||
  !/^postgresql:\/\/postgres:postgres@127\.0\.0\.1:55912\/postgres\?sslmode=disable$/.test(
    dbUrl ?? "",
  ) ||
  !key ||
  !artifact ||
  !artifact.includes("xiaozhuwork-g-upgrade-rehearsal-20261011")
) {
  throw new Error(
    "Refusing held-data rehearsal outside disposable 55912 Supabase",
  );
}

const db = postgres(dbUrl, { ssl: false, max: 2 });
const storage = createClient(apiUrl, key, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const bytes = new TextEncoder().encode(
  "G upgrade rehearsal synthetic file: original immutable payload",
);
const checksum = createHash("sha256").update(bytes).digest("hex");

async function observe(ids) {
  const [project] = await db`select id,name,created_by,leader_id,archived_at
    from public.projects where id=${ids.project}::uuid`;
  const members = await db`select user_id,role,member_state
    from public.project_members where project_id=${ids.project}::uuid order by user_id`;
  const tasks = await db`select id,title,status,assignee_id,weight,deadline_at
    from public.tasks where project_id=${ids.project}::uuid order by id`;
  const [file] = await db`select id,logical_name,current_version_id
    from public.task_files where id=${ids.file}::uuid`;
  const [version] = await db`select id,file_id,version_number,object_path,
      original_name,mime_type,size_bytes,sha256_hex
    from public.task_file_versions where id=${ids.version}::uuid`;
  const [event] = await db`select id,event_type,entity_id,event_data
    from public.business_events where id=${ids.event}::bigint`;
  const [profile] = await db`select display_name from public.profiles
    where id=${ids.owner}::uuid`;
  assert.ok(
    project && file && version && event && profile,
    "held baseline must still exist",
  );
  return { project, members, tasks, file, version, event, profile };
}

async function storageRoundtrip(ids) {
  const { data: signed, error } = await storage.storage
    .from("teamup-files")
    .createSignedUrl(ids.objectPath, 120);
  assert.equal(
    error,
    null,
    "existing object remains authorized for service role",
  );
  const result = await fetch(signed.signedUrl);
  assert.equal(result.status, 200, "original object remains readable");
  const actual = new Uint8Array(await result.arrayBuffer());
  assert.equal(createHash("sha256").update(actual).digest("hex"), checksum);
}

try {
  if (phase === "before") {
    const [migrations] =
      await db`select count(*)::int as total from supabase_migrations.schema_migrations`;
    assert.equal(
      migrations.total,
      baselineMigrations,
      "baseline migration count must match the intended released source",
    );
    const owner = randomUUID(),
      member = randomUUID(),
      project = randomUUID(),
      task = randomUUID();
    const file = randomUUID(),
      objectPath = `g-upgrade-held/${randomUUID()}.pdf`;
    const { error: uploadError } = await storage.storage
      .from("teamup-files")
      .upload(objectPath, bytes, {
        contentType: "application/pdf",
        upsert: false,
      });
    assert.equal(uploadError, null, "F0 Storage upload fixture");

    await db`insert into auth.users(id,email) values
      (${owner}::uuid,${"g-upgrade-owner-" + owner + "@example.test"}),
      (${member}::uuid,${"g-upgrade-member-" + member + "@example.test"})`;
    await db`insert into public.profiles(id,display_name)
      values(${owner}::uuid,'G Upgrade Historical Owner')
      on conflict (id) do update set display_name=excluded.display_name`;
    await db`insert into public.projects(id,name,deadline_at,created_by,leader_id)
      values(${project}::uuid,'G F0 protected academic project',now()+interval '15 days',
        ${owner}::uuid,${owner}::uuid)`;
    await db`insert into public.project_members(
      project_id,user_id,role,member_state,is_observer
    ) values
      (${project}::uuid,${owner}::uuid,'leader','active',false),
      (${project}::uuid,${member}::uuid,'member','active',false)`;
    await db`insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
      assignment_state,version
    ) values(${task}::uuid,${project}::uuid,'Historical accepted task',
      ${owner}::uuid,${member}::uuid,now()+interval '6 days','in_progress',4,
      'assigned',1)`;
    const [reservation] = await db`
      insert into public.file_upload_reservations(
        project_id,task_id,actor_id,mode,object_path,original_name,
        declared_mime_type,declared_size_bytes,expires_at,state
      ) values (
        ${project}::uuid,${task}::uuid,${owner}::uuid,'new_file',
        ${objectPath},'original-evidence.pdf','application/pdf',${bytes.length},
        now()+interval '3 days','finalized'
      ) returning id
    `;
    await db`insert into public.task_files(id,project_id,task_id,logical_name,created_by)
      values(${file}::uuid,${project}::uuid,${task}::uuid,'original-evidence.pdf',
      ${owner}::uuid)`;
    const [version] = await db`
      insert into public.task_file_versions(
        file_id,project_id,task_id,reservation_id,version_number,object_path,
        original_name,mime_type,size_bytes,sha256_hex,uploaded_by
      ) values (
        ${file}::uuid,${project}::uuid,${task}::uuid,${reservation.id}::uuid,1,
        ${objectPath},'original-evidence.pdf','application/pdf',
        ${bytes.length},${checksum},${owner}::uuid
      ) returning id
    `;
    await db`update public.task_files set current_version_id=${version.id}::uuid
      where id=${file}::uuid`;
    const [event] = await db`
      insert into public.business_events(
        project_id,actor_id,event_type,entity_type,entity_id,request_id,event_data
      ) values (
        ${project}::uuid,${owner}::uuid,'task_created','task',${task}::uuid,
        ${randomUUID()}::uuid,
        ${db.json({
          schemaVersion: 1,
          policyVersion: 1,
          occurrenceKey: `g-upgrade:${task}:created`,
          recordedBy: "F0",
          historical: true,
          note: "preserve original evidence",
        })}
      ) returning id
    `;
    const ids = {
      owner,
      member,
      project,
      task,
      file,
      version: version.id,
      event: event.id,
      objectPath,
      checksum,
    };
    const before = await observe(ids);
    assert.equal(before.members.length, 2);
    assert.equal(before.tasks.length, 1);
    await storageRoundtrip(ids);
    await writeFile(
      artifact,
      JSON.stringify({ baselineMigrations, ids, before }, null, 2),
    );
    console.log(
      "PASS F0 held fixture: two users, project, member pair, accepted task, file metadata/version, immutable event and Storage bytes",
    );
  } else {
    const baseline = JSON.parse(await readFile(artifact, "utf8"));
    const { ids, before } = baseline;
    assert.equal(
      baseline.baselineMigrations,
      baselineMigrations,
      "baseline fixture must match the original migration count",
    );
    const after = await observe(ids);
    // Baseline was serialized as JSON: normalize postgres.js Result arrays
    // and timestamptz Date objects to the same on-disk representation.
    assert.deepEqual(
      JSON.parse(JSON.stringify(after)),
      before,
      "historical project, members, task, file and event must remain identical",
    );
    await storageRoundtrip(ids);
    const [reminder] =
      await db`select task_id,deadline_revision from public.task_reminder_deadlines
      where task_id=${ids.task}::uuid`;
    assert.ok(reminder, "A backfills deadline revision for existing task");
    assert.equal(reminder.deadline_revision, 1);
    const [counts] = await db`
      select (select count(*)::int from public.contribution_penalties
        where project_id=${ids.project}::uuid) as penalties,
        (select count(*)::int from public.file_version_withdrawals
        where project_id=${ids.project}::uuid) as withdrawals
    `;
    assert.equal(
      counts.penalties,
      0,
      "historical task must not be back-charged",
    );
    assert.equal(
      counts.withdrawals,
      0,
      "historical file must not be quarantined",
    );
    const [migrationCount] =
      await db`select count(*)::int as total from supabase_migrations.schema_migrations`;
    assert.equal(
      migrationCount.total,
      71,
      "all 71 expected migration versions present exactly once",
    );
    console.log(
      `PASS F0→G held-data upgrade: ${baselineMigrations}→71 migrations; original project, member, task, versioned file, history and object checksum preserved; reminder backfilled; no retroactive penalties/quarantine`,
    );
  }
} finally {
  await db.end({ timeout: 5 });
}
