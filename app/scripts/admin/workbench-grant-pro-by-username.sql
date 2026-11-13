-- XiaozhuWork / Workbench: grant account-level Pro by account display name.
-- This is an administrator-only SQL template; it does NOT run automatically.
-- In Alibaba Cloud ECS Workbench, open PostgreSQL first:
--   docker exec -it supabase-db psql -X -v ON_ERROR_STOP=1 -P pager=off -U postgres -d postgres
-- Paste the entire SQL from BEGIN through COMMIT into psql.
-- Adjust v_display_name, v_duration and v_grant_source below. Exact, trimmed, case-sensitive match.
-- If any other account shares the name (even an unconfirmed account), abort.
-- Only a confirmed auth.users account is eligible. Never use this as a migration.
-- A second successful execution may extend an active entitlement again;
-- therefore active-Pro extension is DISABLED by default.
-- Uses the existing audited entitlement RPC; never UPDATE entitlements directly.

BEGIN;

DO $grant$
DECLARE
  -- ===== Configuration (change these to grant another account) =====
  v_display_name text := 'CHANGE_ME';
  v_duration interval := interval '30 days';
  v_grant_source text := 'CHANGE_ME';
  -- Source must be one of: test / gift / commercial / other.
  -- Set true ONLY when deliberately extending an existing active Pro grant.
  v_allow_active_extension boolean := false;
  -- ================================================================

  v_user_id uuid;
  v_name_matches integer;
  v_existing public.account_entitlements%ROWTYPE;
  v_expected_version integer := 0;
  v_now timestamptz := transaction_timestamp();
  v_start timestamptz;
  v_expiry timestamptz;
  v_request_id uuid := gen_random_uuid();
  v_result jsonb;
  v_mode text;
BEGIN
  IF v_display_name IS NULL
     OR char_length(btrim(v_display_name)) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION '请输入有效账号昵称（1–80 个字符）';
  END IF;

  IF v_duration IS NULL OR v_duration <= interval '0 seconds' THEN
    RAISE EXCEPTION 'Pro 授权时长必须为正数';
  END IF;

  IF v_grant_source IS NULL
     OR v_grant_source NOT IN ('test','gift','commercial','other') THEN
    RAISE EXCEPTION 'v_grant_source must be test / gift / commercial / other';
  END IF;

  -- Resolve against ALL profiles first, not merely confirmed accounts.
  -- This avoids choosing an arbitrary account when nicknames are duplicated.
  SELECT count(*) INTO v_name_matches
  FROM public.profiles p
  WHERE btrim(p.display_name) = btrim(v_display_name);

  IF v_name_matches <> 1 THEN
    RAISE EXCEPTION '昵称“%”匹配 % 个账号；必须恰好匹配 1 个才能授权',
      v_display_name, v_name_matches;
  END IF;

  -- Confirm that the unique nickname belongs to a confirmed auth account;
  -- lock its profile using the same serialization point as the service RPC.
  SELECT p.id INTO v_user_id
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE btrim(p.display_name) = btrim(v_display_name)
    AND u.email_confirmed_at IS NOT NULL
  FOR UPDATE OF p;

  IF NOT FOUND THEN
    RAISE EXCEPTION '昵称“%”的账号未完成邮箱验证；拒绝授权', v_display_name;
  END IF;

  SELECT e.* INTO v_existing
  FROM public.account_entitlements e
  WHERE e.user_id = v_user_id
  FOR UPDATE;

  IF FOUND THEN
    v_expected_version := v_existing.version;
  END IF;

  IF v_existing.plan = 'pro'
     AND v_existing.status = 'active'
     AND v_existing.starts_at <= v_now
     AND v_existing.expires_at > v_now THEN
    IF NOT v_allow_active_extension THEN
      RAISE EXCEPTION '账号“%”已具有有效 Pro；为避免重复续期，默认停止。确需续期时请显式启用 v_allow_active_extension',
        v_display_name;
    END IF;

    -- Deliberate extension: keep the original start and add to old expiry.
    v_start := v_existing.starts_at;
    v_expiry := v_existing.expires_at + v_duration;
    v_mode := '续期';
  ELSE
    -- New, expired, cancelled or scheduled: grant from right now.
    v_start := v_now;
    v_expiry := v_now + v_duration;
    v_mode := '开通或恢复';
  END IF;

  -- Existing service-side version checks, project entitlement handling,
  -- idempotency and immutable audit. This must be the only write entrypoint.
  SELECT public.cmd_set_account_entitlement_service(
    v_user_id, v_request_id, 'pro', 'active',
    v_start, v_expiry, v_expected_version,
    NULL, v_grant_source,
    'Manual Pro grant via uniquely matched display name'
  ) INTO v_result;

  IF COALESCE((v_result->>'ok')::boolean, false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Pro 授权 RPC 失败：%', v_result;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.account_entitlements e
    WHERE e.user_id = v_user_id
      AND e.plan = 'pro'
      AND e.status = 'active'
      AND e.starts_at = v_start
      AND e.expires_at = v_expiry
      AND e.version = v_expected_version + 1
  ) OR private.is_account_pro(v_user_id, v_now) IS DISTINCT FROM true THEN
    RAISE EXCEPTION '授权后的 Pro 状态、期限或版本校验失败，事务将回滚';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.account_entitlement_audit a
    WHERE a.user_id = v_user_id
      AND a.request_id = v_request_id
      AND a.plan = 'pro'
      AND a.status = 'active'
      AND a.grant_source = v_grant_source
      AND a.entitlement_version = v_expected_version + 1
  ) THEN
    RAISE EXCEPTION '授权审计记录不存在，事务将回滚';
  END IF;

  RAISE NOTICE '昵称：% | 用户 ID：% | 操作：% | 北京时间到期：% | 新版本：%',
    v_display_name, v_user_id, v_mode,
    v_expiry AT TIME ZONE 'Asia/Shanghai', v_expected_version + 1;
END;
$grant$;

COMMIT;

-- Optional read-only verification (replace display name as needed):
-- SELECT p.display_name, u.email, e.plan, e.status, e.expires_at,
--        private.is_account_pro(p.id, now()) AS effective_pro, e.version
-- FROM public.profiles p
-- JOIN auth.users u ON u.id = p.id
-- LEFT JOIN public.account_entitlements e ON e.user_id = p.id
-- WHERE btrim(p.display_name) = '示例用户';
