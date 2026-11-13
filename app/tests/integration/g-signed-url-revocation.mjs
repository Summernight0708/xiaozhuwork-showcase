/* global process, TextEncoder, fetch, console */
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url?.startsWith("http://127.0.0.1:55811") || !key)
  throw new Error("Refusing to run outside the isolated G Supabase");
const client = createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const bucket = client.storage.from("teamup-files");
const id = randomUUID();
const oldPath = `g-storage-403-proof/${id}.pdf`;
const quarantinePath = `quarantine/withdrawal/g-http-${id}`;
const payload = new TextEncoder().encode("G HTTP signed URL revocation " + id);
try {
  const { error: uploadError } = await bucket.upload(oldPath, payload, {
    contentType: "application/pdf",
    cacheControl: "0",
    upsert: false,
  });
  assert.equal(uploadError, null, "isolated upload must succeed");
  const { data: signed, error: signError } = await bucket.createSignedUrl(
    oldPath,
    300,
  );
  assert.equal(signError, null, "original signed URL must be granted");
  assert.ok(signed?.signedUrl);
  const before = await fetch(signed.signedUrl, { cache: "no-store" });
  assert.equal(before.status, 200, "pre-withdrawal signed URL must return 200");
  assert.deepEqual(new Uint8Array(await before.arrayBuffer()), payload);
  const { error: moveError } = await bucket.move(oldPath, quarantinePath);
  assert.equal(moveError, null, "Storage move must succeed");
  const after = await fetch(signed.signedUrl, { cache: "no-store" });
  const denialText = await after.text();
  const denied =
    after.status === 403 ||
    after.status === 404 ||
    (after.status === 400 &&
      /Object not found|NoSuchKey|not found/i.test(denialText));
  assert.ok(
    denied,
    `old signed URL must be inaccessible after move, got ${after.status}: ${denialText.slice(0, 220)}`,
  );
  const { data: quarantined, error: quarantineError } =
    await bucket.createSignedUrl(quarantinePath, 300);
  assert.equal(
    quarantineError,
    null,
    "service role may sign quarantined bytes",
  );
  const other = await fetch(quarantined.signedUrl, { cache: "no-store" });
  assert.equal(other.status, 200, "quarantined bytes must exist");
  assert.deepEqual(new Uint8Array(await other.arrayBuffer()), payload);
  console.log(
    `PASS signed-url revocation: before=${before.status}, after=${after.status}, quarantine=${other.status}`,
  );
} finally {
  await bucket.remove([oldPath, quarantinePath]);
}
