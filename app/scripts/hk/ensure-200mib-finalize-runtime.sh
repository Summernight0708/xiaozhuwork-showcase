#!/usr/bin/env bash
# Versioned, scoped fix for Supabase Edge Runtime v1.76.2 / 200 MiB finalize.
# Usage: bash scripts/hk/ensure-200mib-finalize-runtime.sh --check
#        bash scripts/hk/ensure-200mib-finalize-runtime.sh --apply /ABSOLUTE/FRESH/BACKUP/DIR
# Fail closed when upstream runtime changes. No environment secrets are read.
set -Eeuo pipefail

MODE="${1:---check}"
BACKUP_DIR="${2:-}"
ACTIVE=/opt/xiaozhuwork-hk/supabase/volumes/functions/main/index.ts
EDGE_CONTAINER=supabase-edge-functions
ORIGINAL_SHA=90415084389ccc2959e1759fd660b428f01260b873d9e436344e202e13b52139
PATCHED_SHA=b79ec21364d635585159769175c310dc2a332ed146b1a9a7ea136c1164a277f8
EXPECTED_IMAGE=supabase/edge-runtime:v1.76.2

if [[ "$MODE" != "--check" && "$MODE" != "--apply" ]]; then
  echo 'USAGE: --check | --apply /ABSOLUTE/FRESH/BACKUP/DIR' >&2
  exit 2
fi
if [[ "$MODE" == "--apply" && ( "$BACKUP_DIR" != /* || -e "$BACKUP_DIR" ) ]]; then
  echo 'BLOCKED: --apply requires a new, absolute backup directory' >&2
  exit 2
fi

test -f "$ACTIVE"
image=$(docker inspect --format '{{.Config.Image}}' "$EDGE_CONTAINER")
if [[ "$image" != "$EXPECTED_IMAGE" ]]; then
  echo 'BLOCKED: unknown Edge Runtime image; audit patch against upstream' >&2
  exit 1
fi
sha=$(sha256sum "$ACTIVE" | awk '{print $1}')
if [[ "$sha" == "$PATCHED_SHA" ]]; then
  docker exec "$EDGE_CONTAINER" grep -q 'cpuTimeHardLimitMs: 30_000' /home/deno/functions/main/index.ts
  echo 'EDGE_200MIB_FINALIZE_HOTFIX: PRESENT'
  exit 0
fi
if [[ "$sha" != "$ORIGINAL_SHA" ]]; then
  echo 'BLOCKED: main/index.ts does not match either pinned runtime version' >&2
  exit 1
fi
if [[ "$MODE" == "--check" ]]; then
  echo 'EDGE_200MIB_FINALIZE_HOTFIX: MISSING (known original version)' >&2
  exit 1
fi

# Serialize release writes. Prepare a real rollback point before any mutation.
exec 9>/run/lock/xiaozhuwork-edge-finalize-200mib.lock
flock -n 9 || { echo 'BLOCKED: concurrent Edge Runtime release'; exit 1; }
[[ "$(sha256sum "$ACTIVE" | awk '{print $1}')" == "$ORIGINAL_SHA" ]]
mkdir -m 700 "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/edge-main.before-200mib.ts"
cp -p "$ACTIVE" "$BACKUP"
chmod 600 "$BACKUP"
[[ "$(sha256sum "$BACKUP" | awk '{print $1}')" == "$ORIGINAL_SHA" ]]
TMP=$(mktemp "${ACTIVE}.stage.XXXXXX")
ACTIVATED=0
rollback() {
  local error=$?
  trap - ERR
  rm -f "$TMP"
  if [[ "$ACTIVATED" == 1 ]]; then
    cp -p "$BACKUP" "${ACTIVE}.rollback.$$"
    mv -f "${ACTIVE}.rollback.$$" "$ACTIVE"
    docker restart -t 20 "$EDGE_CONTAINER" >/dev/null || true
    echo 'EDGE_200MIB_FINALIZE_HOTFIX: ROLLED_BACK' >&2
  fi
  exit "$error"
}
trap rollback ERR

# The replacements intentionally match only the known v1.76.2 runtime.
python3 - "$ACTIVE" "$TMP" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_bytes()
old_1 = b'  const workerTimeoutMs = 1 * 60 * 1000'
new_1 = (
    b'  // A 200 MiB streaming validator needs a larger, per-function CPU budget.\n'
    b'  // All other Edge workers retain their current limits.\n'
    b"  const isLargeFileFinalizer = service_name === 'finalize-task-file-upload'\n"
    b'  const workerTimeoutMs = isLargeFileFinalizer ? 4 * 60 * 1000 : 1 * 60 * 1000'
)
old_2 = b'      workerTimeoutMs,\n      noModuleCache,'
new_2 = (
    b'      workerTimeoutMs,\n'
    b'      ...(isLargeFileFinalizer\n'
    b'        ? { cpuTimeSoftLimitMs: 15_000, cpuTimeHardLimitMs: 30_000 }\n'
    b'        : {}),\n'
    b'      noModuleCache,'
)
for old, new in ((old_1, new_1), (old_2, new_2)):
    if source.count(old) != 1:
        raise SystemExit('BLOCKED: expected Edge Runtime source expression changed')
    source = source.replace(old, new)
Path(sys.argv[2]).write_bytes(source)
PY

[[ "$(sha256sum "$TMP" | awk '{print $1}')" == "$PATCHED_SHA" ]]
chmod 644 "$TMP"
chown root:root "$TMP"
mv -f "$TMP" "$ACTIVE"
ACTIVATED=1
docker restart -t 20 "$EDGE_CONTAINER" >/dev/null
[[ "$(docker inspect -f '{{.State.Running}}' "$EDGE_CONTAINER")" == true ]]
docker exec "$EDGE_CONTAINER" grep -q 'cpuTimeHardLimitMs: 30_000' /home/deno/functions/main/index.ts
[[ "$(sha256sum "$ACTIVE" | awk '{print $1}')" == "$PATCHED_SHA" ]]
ACTIVATED=0
trap - ERR
echo 'EDGE_200MIB_FINALIZE_HOTFIX: APPLIED_AND_VERIFIED'
