import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const admin = postgres(databaseUrl, { max: 4 });

type RpcResult = {
  ok: boolean;
  code?: string;
  replayed: boolean;
  currentVersion?: number;
  data?: {
    version?: number;
  };
};

async function asService(
  sql: Sql,
  query: (tx: TransactionSql) => PromiseLike<readonly { result: RpcResult }[]>,
): Promise<RpcResult> {
  return sql.begin(async (tx): Promise<RpcResult> => {
    await tx.unsafe("set local role service_role");
    const rows = await query(tx);
    return rows[0]!.result;
  });
}

async function asAuthenticated(
  sql: Sql,
  userId: string,
  query: (tx: TransactionSql) => PromiseLike<readonly { result: RpcResult }[]>,
): Promise<RpcResult> {
  return sql.begin(async (tx): Promise<RpcResult> => {
    await tx`select set_config('request.jwt.claim.sub', ${userId}, true)`;
    await tx.unsafe("set local role authenticated");
    const rows = await query(tx);
    return rows[0]!.result;
  });
}

async function cleanup() {
  await admin.unsafe("set session_replication_role = replica");
  try {
    await admin`delete from public.business_events where project_id::text like 'c2100000-%'`;
    await admin`delete from public.command_requests where project_id::text like 'c2100000-%'`;
    await admin`delete from public.project_pro_grace where project_id::text like 'c2100000-%'`;
    await admin`delete from public.account_entitlement_audit where user_id::text like 'c1100000-%'`;
    await admin`delete from private.account_entitlement_service_commands where request_id::text like 'c9100000-%'`;
    await admin`delete from public.account_entitlements where user_id::text like 'c1100000-%'`;
    await admin`delete from public.project_members where project_id::text like 'c2100000-%'`;
    await admin`delete from public.projects where id::text like 'c2100000-%'`;
    await admin`delete from auth.users where id::text like 'c1100000-%'`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

beforeAll(async () => {
  await cleanup();
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("account Pro entitlement concurrency", () => {
  test("serializes competing account entitlement versions", async () => {
    await admin`
      insert into auth.users(id,email) values
        ('c1100000-0000-0000-0000-000000000001','p0-occ-operator@example.test'),
        ('c1100000-0000-0000-0000-000000000002','p0-occ-target@example.test')
    `;
    await admin`
      insert into public.account_entitlements(
        user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
      ) values(
        'c1100000-0000-0000-0000-000000000002','pro','active',
        now()-interval '1 day',now()+interval '30 days',now(),
        'c1100000-0000-0000-0000-000000000001','test',1
      )
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asService(
        connectionA,
        (tx) =>
          tx`select public.cmd_set_account_entitlement_service(
            'c1100000-0000-0000-0000-000000000002',
            'c9100000-0000-0000-0000-000000000001',
            'pro','active',
            '2026-01-01T00:00:00Z'::timestamptz,
            '2028-01-01T00:00:00Z'::timestamptz,
            1,
            'c1100000-0000-0000-0000-000000000001',
            'test','race-a'
          ) as result`,
      ),
      asService(
        connectionB,
        (tx) =>
          tx`select public.cmd_set_account_entitlement_service(
            'c1100000-0000-0000-0000-000000000002',
            'c9100000-0000-0000-0000-000000000002',
            'pro','active',
            '2026-01-01T00:00:00Z'::timestamptz,
            '2029-01-01T00:00:00Z'::timestamptz,
            1,
            'c1100000-0000-0000-0000-000000000001',
            'test','race-b'
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    expect(results.find((result) => !result.ok)?.currentVersion).toBe(2);

    const rows = await admin<
      { version: number; audit_count: number; command_count: number }[]
    >`
      select
        e.version,
        (select count(*)::integer from public.account_entitlement_audit a
          where a.user_id=e.user_id) as audit_count,
        (select count(*)::integer from private.account_entitlement_service_commands c
          where c.request_id::text like 'c9100000-0000-0000-0000-00000000000%') as command_count
      from public.account_entitlements e
      where e.user_id='c1100000-0000-0000-0000-000000000002'
    `;

    expect(rows[0]!.version).toBe(2);
    expect(rows[0]!.audit_count).toBe(1);
    expect(rows[0]!.command_count).toBe(2);
  });

  test("account cancellation racing member removal preserves one grace window", async () => {
    await admin`
      insert into auth.users(id,email) values
        ('c1100000-0000-0000-0000-000000000010','p0-remove-leader@example.test'),
        ('c1100000-0000-0000-0000-000000000011','p0-remove-target@example.test')
    `;
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'c2100000-0000-0000-0000-000000000010','P0 remove race',now()+interval '10 days',
        'c1100000-0000-0000-0000-000000000010','c1100000-0000-0000-0000-000000000010',1
      )
    `;
    await admin`
      insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
        ('c3100000-0000-0000-0000-000000000010','c2100000-0000-0000-0000-000000000010','c1100000-0000-0000-0000-000000000010','leader','active',false,1),
        ('c3100000-0000-0000-0000-000000000011','c2100000-0000-0000-0000-000000000010','c1100000-0000-0000-0000-000000000011','member','active',false,1)
    `;
    await admin`
      insert into public.account_entitlements(
        user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
      ) values(
        'c1100000-0000-0000-0000-000000000011','pro','active',
        now()-interval '1 day',now()+interval '30 days',now(),
        'c1100000-0000-0000-0000-000000000010','test',1
      )
    `;

    const serviceConnection = postgres(databaseUrl, { max: 1 });
    const memberConnection = postgres(databaseUrl, { max: 1 });
    const [cancelResult, removeResult] = await Promise.all([
      asService(
        serviceConnection,
        (tx) =>
          tx`select public.cmd_set_account_entitlement_service(
            'c1100000-0000-0000-0000-000000000011',
            'c9100000-0000-0000-0000-000000000010',
            'pro','cancelled',
            '2026-01-01T00:00:00Z'::timestamptz,
            '2028-01-01T00:00:00Z'::timestamptz,
            1,
            'c1100000-0000-0000-0000-000000000010',
            'test','cancel-vs-remove'
          ) as result`,
      ),
      asAuthenticated(
        memberConnection,
        "c1100000-0000-0000-0000-000000000010",
        (tx) =>
          tx`select public.cmd_remove_project_member(
            'c2100000-0000-0000-0000-000000000010',
            'c3100000-0000-0000-0000-000000000011',
            'c9100000-0000-0000-0000-000000000011',
            1
          ) as result`,
      ),
    ]);
    await Promise.all([serviceConnection.end(), memberConnection.end()]);

    expect(cancelResult.ok).toBe(true);
    expect(removeResult.ok).toBe(true);

    const rows = await admin<
      {
        entitlement_status: string;
        member_state: string;
        project_state: string;
        grace_count: number;
        grace_version: number;
        grace_reason: string;
        grace_seconds: number;
        audit_count: number;
      }[]
    >`
      select
        (select status from public.account_entitlements
          where user_id='c1100000-0000-0000-0000-000000000011') as entitlement_status,
        (select member_state from public.project_members
          where id='c3100000-0000-0000-0000-000000000011') as member_state,
        (select state from private.resolve_project_entitlement(
          'c2100000-0000-0000-0000-000000000010',now()
        )) as project_state,
        (select count(*)::integer from public.project_pro_grace
          where project_id='c2100000-0000-0000-0000-000000000010') as grace_count,
        (select version from public.project_pro_grace
          where project_id='c2100000-0000-0000-0000-000000000010') as grace_version,
        (select reason from public.project_pro_grace
          where project_id='c2100000-0000-0000-0000-000000000010') as grace_reason,
        (select extract(epoch from (expires_at-started_at))::integer
          from public.project_pro_grace
          where project_id='c2100000-0000-0000-0000-000000000010') as grace_seconds,
        (select count(*)::integer from public.account_entitlement_audit
          where user_id='c1100000-0000-0000-0000-000000000011') as audit_count
    `;

    expect(rows[0]!.entitlement_status).toBe("cancelled");
    expect(rows[0]!.member_state).toBe("removed");
    expect(rows[0]!.project_state).toBe("grace");
    expect(rows[0]!.grace_count).toBe(1);
    // Either serialized path may create the single grace row first; a later refresh bumps its version.
    expect([1, 2]).toContain(rows[0]!.grace_version);
    expect(["account_cancelled", "member_removed"]).toContain(
      rows[0]!.grace_reason,
    );
    expect(rows[0]!.grace_seconds).toBe(3 * 24 * 60 * 60);
    expect(rows[0]!.audit_count).toBe(1);
  });

  test("account cancellation racing observer transition preserves one grace window", async () => {
    await admin`
      insert into auth.users(id,email) values
        ('c1100000-0000-0000-0000-000000000020','p0-observer-leader@example.test'),
        ('c1100000-0000-0000-0000-000000000021','p0-observer-target@example.test')
    `;
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'c2100000-0000-0000-0000-000000000020','P0 observer race',now()+interval '10 days',
        'c1100000-0000-0000-0000-000000000020','c1100000-0000-0000-0000-000000000020',1
      )
    `;
    await admin`
      insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
        ('c3100000-0000-0000-0000-000000000020','c2100000-0000-0000-0000-000000000020','c1100000-0000-0000-0000-000000000020','leader','active',false,1),
        ('c3100000-0000-0000-0000-000000000021','c2100000-0000-0000-0000-000000000020','c1100000-0000-0000-0000-000000000021','member','active',false,1)
    `;
    await admin`
      insert into public.account_entitlements(
        user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
      ) values(
        'c1100000-0000-0000-0000-000000000021','pro','active',
        now()-interval '1 day',now()+interval '30 days',now(),
        'c1100000-0000-0000-0000-000000000020','test',1
      )
    `;

    const serviceConnection = postgres(databaseUrl, { max: 1 });
    const memberConnection = postgres(databaseUrl, { max: 1 });
    const [cancelResult, roleResult] = await Promise.all([
      asService(
        serviceConnection,
        (tx) =>
          tx`select public.cmd_set_account_entitlement_service(
            'c1100000-0000-0000-0000-000000000021',
            'c9100000-0000-0000-0000-000000000020',
            'pro','cancelled',
            '2026-01-01T00:00:00Z'::timestamptz,
            '2028-01-01T00:00:00Z'::timestamptz,
            1,
            'c1100000-0000-0000-0000-000000000020',
            'test','cancel-vs-observer'
          ) as result`,
      ),
      asAuthenticated(
        memberConnection,
        "c1100000-0000-0000-0000-000000000020",
        (tx) =>
          tx`select public.cmd_update_project_member_role(
            'c2100000-0000-0000-0000-000000000020',
            'c3100000-0000-0000-0000-000000000021',
            'observer',
            'c9100000-0000-0000-0000-000000000021',
            1
          ) as result`,
      ),
    ]);
    await Promise.all([serviceConnection.end(), memberConnection.end()]);

    expect(cancelResult.ok).toBe(true);
    expect(roleResult.ok).toBe(true);

    const rows = await admin<
      {
        entitlement_status: string;
        member_role: string;
        is_observer: boolean;
        project_state: string;
        grace_count: number;
        grace_version: number;
        grace_reason: string;
      }[]
    >`
      select
        (select status from public.account_entitlements
          where user_id='c1100000-0000-0000-0000-000000000021') as entitlement_status,
        (select role from public.project_members
          where id='c3100000-0000-0000-0000-000000000021') as member_role,
        (select is_observer from public.project_members
          where id='c3100000-0000-0000-0000-000000000021') as is_observer,
        (select state from private.resolve_project_entitlement(
          'c2100000-0000-0000-0000-000000000020',now()
        )) as project_state,
        (select count(*)::integer from public.project_pro_grace
          where project_id='c2100000-0000-0000-0000-000000000020') as grace_count,
        (select version from public.project_pro_grace
          where project_id='c2100000-0000-0000-0000-000000000020') as grace_version,
        (select reason from public.project_pro_grace
          where project_id='c2100000-0000-0000-0000-000000000020') as grace_reason
    `;

    expect(rows[0]!.entitlement_status).toBe("cancelled");
    expect(rows[0]!.member_role).toBe("observer");
    expect(rows[0]!.is_observer).toBe(true);
    expect(rows[0]!.project_state).toBe("grace");
    expect(rows[0]!.grace_count).toBe(1);
    // Either serialized path may create the single grace row first; a later refresh bumps its version.
    expect([1, 2]).toContain(rows[0]!.grace_version);
    expect(["account_cancelled", "member_became_observer"]).toContain(
      rows[0]!.grace_reason,
    );
  });
});
