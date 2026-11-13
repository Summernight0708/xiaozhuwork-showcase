#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKER="$ROOT/deploy/hk/followup-workers/xiaozhuwork-followup-workers"
BRIDGE="$ROOT/deploy/hk/followup-workers/xiaozhuwork-followup-worker-bridge"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash -n "$WORKER"
bash -n "$BRIDGE"

# Stub HTTP transport; never send a real request or read real credentials.
cat > "$TMP/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${!#}" >> "$XIAOZHUWORK_WORKER_CALL_LOG"
STUB
chmod 700 "$TMP/curl"
export PATH="$TMP:$PATH"
export XIAOZHUWORK_WORKER_CALL_LOG="$TMP/worker-calls"
export XIAOZHUWORK_API_URL="http://127.0.0.1:59999"
export XIAOZHUWORK_SERVICE_ROLE_JWT="synthetic-worker-service-jwt-not-real"
export TASK_REMINDER_CRON_SECRET="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
export CONTRIBUTION_PENALTY_CRON_SECRET="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
export FILE_WITHDRAWAL_CRON_SECRET="cccccccccccccccccccccccccccccccc"
export LIFECYCLE_SCHEDULER_SECRET="dddddddddddddddddddddddddddddddd"

export XIAOZHUWORK_ENABLE_PENALTIES=0 XIAOZHUWORK_ENABLE_LIFECYCLE=0
unset LIFECYCLE_AUTH_REVOCATION_ENABLED || true
bash "$WORKER" >"$TMP/output"
[[ "$(wc -l <"$XIAOZHUWORK_WORKER_CALL_LOG")" == 2 ]]
grep -Fx "http://127.0.0.1:59999/functions/v1/task-deadline-reminders" "$XIAOZHUWORK_WORKER_CALL_LOG" >/dev/null
grep -Fx "http://127.0.0.1:59999/functions/v1/process-file-withdrawals" "$XIAOZHUWORK_WORKER_CALL_LOG" >/dev/null

: > "$XIAOZHUWORK_WORKER_CALL_LOG"
export XIAOZHUWORK_ENABLE_PENALTIES=1 XIAOZHUWORK_ENABLE_LIFECYCLE=1
export LIFECYCLE_AUTH_REVOCATION_ENABLED=false
bash "$WORKER" >"$TMP/output"
[[ "$(wc -l <"$XIAOZHUWORK_WORKER_CALL_LOG")" == 4 ]]
grep -Fx "http://127.0.0.1:59999/functions/v1/dispatch-contribution-penalties" "$XIAOZHUWORK_WORKER_CALL_LOG" >/dev/null
grep -Fx "http://127.0.0.1:59999/functions/v1/lifecycle-worker" "$XIAOZHUWORK_WORKER_CALL_LOG" >/dev/null

# Missing or true Auth-revocation guard must fail before dispatching anything.
: > "$XIAOZHUWORK_WORKER_CALL_LOG"
export LIFECYCLE_AUTH_REVOCATION_ENABLED=true
set +e
bash "$WORKER" >"$TMP/output" 2>"$TMP/error"
status=$?
set -e
[[ "$status" == 78 ]]
[[ ! -s "$XIAOZHUWORK_WORKER_CALL_LOG" ]]

# Invalid feature switch and short secrets fail closed before HTTP.
: > "$XIAOZHUWORK_WORKER_CALL_LOG"
export XIAOZHUWORK_ENABLE_PENALTIES=maybe XIAOZHUWORK_ENABLE_LIFECYCLE=0
set +e
bash "$WORKER" >"$TMP/output" 2>"$TMP/error"
status=$?
set -e
[[ "$status" == 78 ]]
[[ ! -s "$XIAOZHUWORK_WORKER_CALL_LOG" ]]

export XIAOZHUWORK_ENABLE_PENALTIES=0
export TASK_REMINDER_CRON_SECRET=short
set +e
bash "$WORKER" >"$TMP/output" 2>"$TMP/error"
status=$?
set -e
[[ "$status" == 78 ]]
[[ ! -s "$XIAOZHUWORK_WORKER_CALL_LOG" ]]

echo 'HK follow-up Worker mock HTTP dispatch and fail-closed gates: PASS'
