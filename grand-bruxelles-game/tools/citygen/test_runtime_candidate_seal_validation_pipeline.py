#!/usr/bin/env python3
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-runtime-candidate-frontier.yml"
text = WORKFLOW.read_text(encoding="utf-8")

required = (
    "python3 grand-bruxelles-game/tools/citygen/test_seal_runtime_candidate_bundle.py",
    "python3 grand-bruxelles-game/tools/citygen/test_validate_runtime_candidate_bundle.py",
    "Seal candidate bundles as QA-only before validation",
    "seal_runtime_candidate_bundle.py",
    "grand-bruxelles-urbis-built-cell-v1",
    "grand-bruxelles-urbis-built-cell-candidate-v1",
    "Refresh frontier digests after QA sealing",
    "Validate candidate bundles against current durable sources",
    "runtime_mount_authorized",
    "jouable_promotion_authorized",
)
for marker in required:
    assert marker in text, marker

compile_at = text.index("Compile next municipality-balanced runtime candidate batch")
seal_at = text.index("Seal candidate bundles as QA-only before validation")
refresh_at = text.index("Refresh frontier digests after QA sealing")
validate_at = text.index("Validate candidate bundles against current durable sources")
persist_at = text.index("Persist candidate-only runtime bundles off main")
assert compile_at < seal_at < refresh_at < validate_at < persist_at

assert "runtime_mount_authorized=true" not in text
assert "jouable_promotion_authorized=true" not in text

print("RUNTIME_CANDIDATE_SEAL_VALIDATION_PIPELINE_OK seal_before_validate=true digest_refresh=true candidate_only=true promotion_bypass=false")
