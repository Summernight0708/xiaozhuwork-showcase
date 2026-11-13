// Service-only scheduler endpoint. Default flags permit only nondestructive SQL.
// Auth soft deletion below is irreversible and requires both flags AND the
// independently approved, generation-bound durable privacy/retention manifest.
// Deployment and the independent deletion Release Gate belong to G.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function constantTimeEqual(left: string, right: string) {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i += 1) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);
  }
  const schedulerSecret = Deno.env.get("LIFECYCLE_SCHEDULER_SECRET") ?? "";
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (schedulerSecret.length < 32 || !url || !serviceKey) {
    return json({ ok: false, code: "WORKER_NOT_CONFIGURED" }, 503);
  }
  if (
    !constantTimeEqual(
      request.headers.get("x-lifecycle-scheduler-secret") ?? "",
      schedulerSecret,
    )
  ) {
    return json({ ok: false, code: "FORBIDDEN" }, 403);
  }
  const client = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    // Auth revocation is opt-in, in addition to the scheduler key. Never
    // run against a pending cancellation window or a different generation.
    // The candidate RPC enforces expiry, service_role, and a small batch.
    let sessionsRevoked = 0;
    if (Deno.env.get("LIFECYCLE_AUTH_REVOCATION_ENABLED") === "true") {
      const { data: candidates, error: candidateError } = await client.rpc(
        "lifecycle_list_expired_revocation_candidates_service",
        { p_batch_limit: 10 },
      );
      if (candidateError || !Array.isArray(candidates)) {
        return json({ ok: false, code: "AUTH_QUEUE_UNAVAILABLE" }, 503);
      }
      for (
        const item of candidates as Array<{
          user_id: string;
          generation: number;
        }>
      ) {
        if (!item.user_id || !Number.isSafeInteger(item.generation)) {
          return json({ ok: false, code: "INVALID_AUTH_CANDIDATE" }, 503);
        }
        // GoTrue ban prevents new sign-ins. It does NOT end old sessions;
        // the guarded service RPC below revokes every refresh token/session,
        // then proves the ban + generation before recording the checkpoint.
        const { error: banError } = await client.auth.admin.updateUserById(
          item.user_id,
          { ban_duration: "876000h" },
        );
        if (banError) {
          console.error("Auth ban failed", banError.status);
          return json({ ok: false, code: "AUTH_BAN_FAILED" }, 503);
        }
        const { data: result, error: revokeError } = await client.rpc(
          "lifecycle_finalize_auth_revocation_service",
          { p_user: item.user_id, p_generation: item.generation },
        );
        if (revokeError || (result as { ok?: boolean } | null)?.ok !== true) {
          console.error("Auth revocation checkpoint failed", revokeError?.code);
          return json({ ok: false, code: "AUTH_REVOCATION_FAILED" }, 503);
        }
        sessionsRevoked += 1;
      }
    }
    // An independent opt-in gate, after the 30-day cancellation window and
    // verified session revocation. GoTrue soft-delete preserves auth.users.id,
    // avoiding unsafe ON DELETE CASCADE of other members' project evidence.
    let authSoftDeleted = 0;
    if (Deno.env.get("LIFECYCLE_AUTH_SOFT_DELETE_ENABLED") === "true") {
      if (Deno.env.get("LIFECYCLE_AUTH_REVOCATION_ENABLED") !== "true") {
        return json(
          { ok: false, code: "SOFT_DELETE_REQUIRES_REVOCATION" },
          503,
        );
      }
      const { data: deletionCandidates, error: deletionError } = await client
        .rpc("lifecycle_list_soft_delete_candidates_service", {
          p_batch_limit: 10,
        });
      if (deletionError || !Array.isArray(deletionCandidates)) {
        return json({ ok: false, code: "SOFT_DELETE_QUEUE_UNAVAILABLE" }, 503);
      }
      for (
        const item of deletionCandidates as Array<{
          user_id: string;
          generation: number;
        }>
      ) {
        if (!item.user_id || !Number.isSafeInteger(item.generation)) {
          return json(
            { ok: false, code: "INVALID_SOFT_DELETE_CANDIDATE" },
            503,
          );
        }
        const target = { p_user: item.user_id, p_generation: item.generation };
        const { data: prepared, error: prepareError } = await client.rpc(
          "lifecycle_prepare_soft_delete_service",
          target,
        );
        if (
          prepareError || (prepared as { ok?: boolean } | null)?.ok !== true
        ) {
          return json({ ok: false, code: "SOFT_DELETE_PREPARE_FAILED" }, 503);
        }
        // Reconcile first: a prior Worker may have crashed after GoTrue
        // completed an irreversible soft delete but before SQL checkpoint.
        let { data: proof, error: proofError } = await client.rpc(
          "lifecycle_finalize_soft_delete_service",
          target,
        );
        if (proofError) {
          return json(
            { ok: false, code: "SOFT_DELETE_PROOF_UNAVAILABLE" },
            503,
          );
        }
        if ((proof as { ok?: boolean } | null)?.ok !== true) {
          if (
            (proof as { code?: string } | null)?.code !==
              "AUTH_SOFT_DELETE_NOT_VERIFIED"
          ) {
            return json({ ok: false, code: "SOFT_DELETE_NOT_DUE" }, 503);
          }
          const { error: softDeleteError } = await client.auth.admin.deleteUser(
            item.user_id,
            true,
          );
          if (softDeleteError) {
            console.error("GoTrue soft delete failed", softDeleteError.status);
            return json({ ok: false, code: "AUTH_SOFT_DELETE_FAILED" }, 503);
          }
          const verification = await client.rpc(
            "lifecycle_finalize_soft_delete_service",
            target,
          );
          proof = verification.data;
          proofError = verification.error;
          if (
            proofError ||
            (proof as { ok?: boolean } | null)?.ok !== true
          ) {
            return json({ ok: false, code: "SOFT_DELETE_PROOF_FAILED" }, 503);
          }
        }
        authSoftDeleted += 1;
      }
    }
    // SQL enforces batch range and service_role, independently of this endpoint.
    const { data, error } = await client.rpc("lifecycle_worker_tick", {
      p_batch_limit: 25,
    });
    if (error) return json({ ok: false, code: "WORKER_SQL_FAILED" }, 503);
    const details = data as {
      account?: { irreversibleDeletes?: number };
      projects?: { irreversibleDeletes?: number };
    } | null;
    if (
      !details ||
      details.account?.irreversibleDeletes !== 0 ||
      details.projects?.irreversibleDeletes !== 0
    ) {
      return json({ ok: false, code: "IRREVERSIBLE_SAFETY_GATE_FAILED" }, 503);
    }
    return json(
      { ok: true, sessionsRevoked, authSoftDeleted, result: data },
      200,
    );
  } catch {
    return json({ ok: false, code: "WORKER_UNEXPECTED_FAILURE" }, 503);
  }
});
