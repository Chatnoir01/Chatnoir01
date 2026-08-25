from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
EXPECTED_SCHEMA = "grand-bruxelles-shared-environment-lifecycle-contract-v1"
LEGACY_POLL_RE = re.compile(r"for\s+[^\n]+\s+in\s+range\(\s*(120|180|240)\s*\)")


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> None:
    if not CONTRACT_PATH.is_file():
        fail("shared Environment lifecycle contract missing")

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("schema") != EXPECTED_SCHEMA:
        fail("shared Environment lifecycle contract schema mismatch")
    if contract.get("runtime_policy") != "dormant_event_driven_nested_mount_safe":
        fail("shared Environment lifecycle policy mismatch")
    if contract.get("legitimate_absence_is_failure") is not False:
        fail("legitimate partial-mount absence must remain dormant")
    if contract.get("geometry_or_material_change_authorized") is not False:
        fail("lifecycle contract must not authorize geometry/material changes")

    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list) or len(runtimes) < 12:
        fail("shared Environment lifecycle runtime registry is incomplete")

    seen: set[str] = set()
    for entry in runtimes:
        if not isinstance(entry, dict):
            fail("malformed lifecycle runtime entry")
        rel_path = entry.get("path")
        if not isinstance(rel_path, str) or not rel_path.startswith("game/scripts/"):
            fail("invalid lifecycle runtime path")
        if rel_path in seen:
            fail(f"duplicate lifecycle runtime path: {rel_path}")
        seen.add(rel_path)
        if entry.get("event_signal") != "SceneTree.node_added":
            fail(f"runtime lost node_added lifecycle contract: {rel_path}")
        if entry.get("nested_mount_recovery") is not True:
            fail(f"runtime lost bounded nested-mount recovery contract: {rel_path}")
        if entry.get("late_child_bind") not in (True, False):
            fail(f"runtime late-child policy missing: {rel_path}")

        script_path = ROOT / rel_path
        if not script_path.is_file():
            fail(f"registered lifecycle runtime missing: {rel_path}")
        source = script_path.read_text(encoding="utf-8")
        if LEGACY_POLL_RE.search(source):
            fail(f"legacy 120/180/240-frame global polling reintroduced: {rel_path}")
        if "node_added" not in source:
            fail(f"event-driven wakeup missing from runtime: {rel_path}")

    print(
        "SHARED_ENVIRONMENT_LIFECYCLE_CONTRACT_OK: "
        f"runtimes={len(runtimes)} legacy_polling=0 policy=dormant_event_driven_nested_mount_safe"
    )


if __name__ == "__main__":
    main()
