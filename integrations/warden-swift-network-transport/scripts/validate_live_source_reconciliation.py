#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence" / "live-source-reconciliation-2026-08-06.json"

with EVIDENCE.open(encoding="utf-8") as handle:
    record = json.load(handle)

errors: list[str] = []

if record.get("record_type") != "WARDEN_SUPABASE_LIVE_SOURCE_RECONCILIATION":
    errors.append("unexpected record_type")

if record.get("project", {}).get("project_ref") != "ayrivdysmbphhlqjmdtc":
    errors.append("unexpected Supabase project reference")

boundary = record.get("authority_boundary", {})
for key in (
    "this_record_grants_authority",
    "this_record_approves_deployment",
    "this_record_activates_tenant_or_connector",
    "this_record_issues_vsr_licence",
):
    if boundary.get(key) is not False:
        errors.append(f"{key} must remain false")

if not str(boundary.get("release_state", "")).startswith("BLOCKED_"):
    errors.append("release_state must remain fail-closed")

functions = record.get("edge_functions")
if not isinstance(functions, list) or {item.get("slug") for item in functions} != {
    "warden-ingest",
    "typeform-mcp-license-intake",
}:
    errors.append("exactly the two reconciled Edge Functions must be registered")
else:
    for item in functions:
        for field in ("live_bundle_sha256", "source_blob_sha"):
            value = str(item.get(field, ""))
            if not re.fullmatch(r"[0-9a-f]{40,64}", value):
                errors.append(f"{item.get('slug')} has invalid {field}")
        if "PENDING" not in str(item.get("mapping_status", "")):
            errors.append(f"{item.get('slug')} mapping must remain pending until reproducible")
        source_path = ROOT.parent.parent / str(item.get("source_path", ""))
        if not source_path.is_file():
            errors.append(f"missing source path for {item.get('slug')}: {source_path}")

migrations = record.get("migrations", {})
if migrations.get("live_inventory_status") != "UNVERIFIED_DATABASE_RECOVERY_MODE":
    errors.append("migration inventory status must honestly remain unverified")
if not str(migrations.get("release_effect", "")).startswith("BLOCKED_"):
    errors.append("migration release effect must remain blocked")
for path in migrations.get("declared_source_paths", []):
    source_path = ROOT.parent.parent / path
    if not source_path.is_file():
        errors.append(f"missing declared migration source: {path}")

if record.get("riveros_evidence_reference") != "PENDING_RECONCILIATION_RECEIPT":
    errors.append("RiverOS receipt must not be fabricated")

if errors:
    print("Warden live-source reconciliation validation failed:")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("Warden live-source reconciliation is structurally valid and remains fail-closed.")
