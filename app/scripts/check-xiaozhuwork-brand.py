#!/usr/bin/env python3
"""Fail if active XiaozhuWork source still contains accidental legacy branding."""
from pathlib import Path
import subprocess
import re
import collections
import sys

root = Path(__file__).resolve().parents[1]
legacy_pattern = re.compile("team" + "up", re.IGNORECASE)
archived = (
    "supabase/migrations/", "docs/superpowers/", "docs/updates/",
    "docs/handoff/", "docs/frontend-ui-v1/", "docs/release/",
)
# These are database contracts, not marketing labels. Renaming requires an independent
# migration and physical file / RLS validation.
stable = re.compile(
    "team" + "up-(?:files|appearance)|team" + "up_(?:active_upload_reservation|"
    "storage_reserved_upload_allowed|visible_file_version_object|appearance|files_insert_reserved|files_select_finalized|files_reject_archived_upload)",
    re.IGNORECASE,
)
exceptions = {
    "tests/unit/brand-assets.spec.ts",
    "tests/unit/upgrade-view.spec.ts",
    "docs/xiaozhuwork-identity-compatibility.md",
    "scripts/check-xiaozhuwork-brand.py",
}
files = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"]).split(b"\0")
counts = collections.Counter()
bad = []
for encoded in files:
    if not encoded:
        continue
    name = encoded.decode("utf-8", errors="surrogateescape").replace("\\", "/")
    path = root / name
    if not path.is_file():
        continue
    try:
        source = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for number, line in enumerate(source.splitlines(), 1):
        if not legacy_pattern.search(line):
            continue
        if name.startswith(archived):
            counts["immutable_historical"] += 1
        elif name == "deploy/hk/umami/privacy-hardening.sql" and "team" + "up_redact_precise_geo" in line:
            counts["umami_upgrade_compatibility"] += 1
        elif name in exceptions:
            counts["documented_compat_or_negative_test"] += 1
        elif name == "src/types/database.generated.ts":
            counts["generated_database_types"] += 1
        elif not legacy_pattern.search(stable.sub("", re.sub("team" + "up_files_(?:insert_reserved|select_finalized|reject_archived_upload)", "", line, flags=re.IGNORECASE))):
            counts["stable_storage_and_sql_contracts"] += 1
        else:
            bad.append(f"{name}:{number}:{line.strip()[:160]}")
print("XiaozhuWork branding audit")
for category, count in sorted(counts.items()):
    print(f"  allowed {category}: {count} lines")
print(f"  unexpected active-source matches: {len(bad)}")
for entry in bad[:100]:
    print("  ERROR " + entry)
sys.exit(1 if bad else 0)
