-- 小猪作业 / XiaozhuWork - Workbench 手动开通或续期 Pro
--
-- 使用方法：
-- 1. 在阿里云 ECS Workbench 的 Linux Shell 进入 PostgreSQL：
--    docker exec -it supabase-db psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres
-- 2. 修改下面 v_email、v_duration 和 v_grant_source 三行，然后把整份 SQL 粘贴到 postgres=# 执行。
-- 3. 仅用于受权的数据库运维人员；使用现有 service RPC 和审计，不直接 UPDATE 权益表。
-- 4. 每成功执行一次就是新增一笔授权；不要因 UI 没立即刷新而重复执行！
-- 5. 出错时整个事务回滚；不要在 psql 中手动忽略异常继续 COMMIT。
--
-- 时长示例：interval '7 days' / interval '30 days' /
--           interval '6 months' / interval '1 year' / interval '100 years'
-- 有效 Pro：从当前到期日顺延；首次、已过期或已取消：从本次授权时间起算。
-- 注意：工作区中的此文件是操作模板，不是数据库迁移；不要加入 supabase/migrations。

BEGIN;

DO $grant$
DECLARE
  -- ===== 每次执行前，只修改这三行 =====
  v_email text := 'CHANGE_ME@example.com';
  v_duration interval := interval '30 days';
  v_grant_source text := 'CHANGE_ME';
  -- 来源只能是 test / gift / commercial / other。
  -- ==================================

  v_user_id uuid;
  v_existing public.account_entitlements%ROWTYPE;
  v_expected_version integer := 0;
  v_now timestamptz := transaction_timestamp();
  v_start timestamptz;
  v_expiry timestamptz;
  v_request_id uuid := gen_random_uuid();
  v_result jsonb;
  v_mode text;
BEGIN
  -- 保守校验：必须明确指定目标邮箱、正数授权时长。
  IF btrim(v_email) = ''
     OR lower(btrim(v_email)) = 'change_me@example.com'
     OR position('@' IN btrim(v_email)) <= 1 THEN
    RAISE EXCEPTION '请先填写要开通 Pro 的真实邮箱';
  END IF;

  IF v_duration <= interval '0 seconds' THEN
    RAISE EXCEPTION '授权时长必须大于零';
  END IF;

  IF v_grant_source IS NULL
     OR v_grant_source NOT IN ('test','gift','commercial','other') THEN
    RAISE EXCEPTION '请将 v_grant_source 明确设置为 test / gift / commercial / other 之一';
  END IF;

  -- 精确匹配已确认邮箱的真实 Auth 账号；不存在或重复时拒绝修改。
  SELECT u.id
  INTO STRICT v_user_id
  FROM auth.users u
  WHERE lower(u.email) = lower(btrim(v_email))
    AND u.email_confirmed_at IS NOT NULL;

  -- 与服务端 RPC 使用相同的资料行锁；避免与同时进行的人工授权冲突。
  PERFORM 1
  FROM public.profiles p
  WHERE p.id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '目标账号缺少 profiles 记录，不予授权';
  END IF;

  SELECT e.*
  INTO v_existing
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
    -- 续期：保留原始起点，在旧到期日后顺延（不会吞掉剩余天数）。
    v_start := v_existing.starts_at;
    v_expiry := v_existing.expires_at + v_duration;
    v_mode := '续期';
  ELSE
    -- 新开通 / 已过期 / 已取消：从现在开始计时。
    v_start := v_now;
    v_expiry := v_now + v_duration;
    v_mode := '开通或恢复';
  END IF;

  -- 唯一业务写入点：由已上线的正式 RPC 负责版本、并发、项目权益和审计。
  SELECT public.cmd_set_account_entitlement_service(
    v_user_id,
    v_request_id,
    'pro',
    'active',
    v_start,
    v_expiry,
    v_expected_version,
    NULL,
    v_grant_source,
    'Manually authorized timed Pro via ECS Workbench'
  ) INTO v_result;

  IF COALESCE((v_result->>'ok')::boolean, false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Pro 授权失败：%', v_result;
  END IF;

  IF private.is_account_pro(v_user_id, v_now) IS DISTINCT FROM true THEN
    RAISE EXCEPTION '授权结果没有立即生效，已取消本次事务';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.account_entitlement_audit a
    WHERE a.user_id = v_user_id
      AND a.request_id = v_request_id
      AND a.plan = 'pro'
      AND a.status = 'active'
      AND a.grant_source = v_grant_source
      AND a.entitlement_version = v_expected_version + 1
  ) THEN
    RAISE EXCEPTION '未找到对应审计记录，已取消本次事务';
  END IF;

  RAISE NOTICE '授权完成：% | 操作：% | 到期：% | 新版本：%',
    v_email, v_mode, v_expiry AT TIME ZONE 'Asia/Shanghai',
    v_expected_version + 1;
END;
$grant$;

COMMIT;

-- 查询当前权益（可选）：将邮箱替换成实际授权邮箱后单独执行。
-- SELECT u.email, e.plan, e.status, e.starts_at, e.expires_at, e.version,
--        private.is_account_pro(u.id, now()) AS effective_pro
-- FROM auth.users u
-- LEFT JOIN public.account_entitlements e ON e.user_id = u.id
-- WHERE lower(u.email) = lower('CHANGE_ME@example.com');
