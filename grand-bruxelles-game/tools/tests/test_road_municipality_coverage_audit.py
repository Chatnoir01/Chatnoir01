#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_municipality_coverage_audit.py"
spec = importlib.util.spec_from_file_location("road_municipality_audit", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def build_real():
    return module.build_audit(
        ROOT / "data" / "osm",
        ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json",
        ROOT / "tools" / "build_road_destination_catalog.py",
        ROOT / "tools" / "build_road_destination_provenance_binding.py",
    )


def test_real_audit_is_deterministic_and_closed() -> None:
    first = build_real()
    second = build_real()
    module.validate_audit(first)
    module.validate_audit(second)
    assert module.canonical_json(first) == module.canonical_json(second)
    assert first["source_entry_count"] == 139
    assert first["registered_not_rendered_count"] == 96
    assert first["discovered_unassigned_count"] == 43
    assert first["municipality_count_with_registered_evidence"] == 3
    assert len(first["discovered_unassigned_road_osm_ids"]) == 43
    assert first["automatic_19_commune_completion_claimed"] is False
    assert first["coverage_scope"] == "registered-evidence-only"
    assert first["authorization"]["source_registration_authorized"] is False
    assert first["authorization"]["road_cell_mapping_authorized"] is False
    for key in ("render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"):
        assert first["authorization"][key] is False
    seen = set()
    for row in first["municipalities"]:
        assert row["niscode"] not in seen
        seen.add(row["niscode"])
        assert row["readiness"] == "REGISTERED_NOT_RENDERED"
        assert row["registered_road_count"] == len(row["registered_road_osm_ids"])
        assert row["cell_count"] == len(row["cell_ids"])
        assert row["cell_manifest_paths"]
        assert row["cell_manifest_sha256"]


def test_hash_tamper_fails_closed() -> None:
    audit = build_real()
    audit["discovered_unassigned_count"] -= 1
    try:
        module.validate_audit(audit)
    except SystemExit as exc:
        assert "accounting drift" in str(exc) or "audit sha drift" in str(exc)
    else:
        raise AssertionError("tampered audit did not fail closed")


def test_false_19_commune_completion_fails_closed_even_rehashed() -> None:
    audit = build_real()
    audit["automatic_19_commune_completion_claimed"] = True
    unsigned = dict(audit)
    unsigned.pop("audit_sha256", None)
    audit["audit_sha256"] = module.sha256_json(unsigned)
    try:
        module.validate_audit(audit)
    except SystemExit as exc:
        assert "coverage claim drift" in str(exc)
    else:
        raise AssertionError("false regional completion claim did not fail closed")


def test_opened_runtime_authorization_fails_closed_even_rehashed() -> None:
    audit = build_real()
    audit["authorization"]["runtime_mount_authorized"] = True
    unsigned = dict(audit)
    unsigned.pop("audit_sha256", None)
    audit["audit_sha256"] = module.sha256_json(unsigned)
    try:
        module.validate_audit(audit)
    except SystemExit as exc:
        assert "opened runtime_mount_authorized" in str(exc)
    else:
        raise AssertionError("opened runtime authorization did not fail closed")


def main() -> int:
    test_real_audit_is_deterministic_and_closed()
    test_hash_tamper_fails_closed()
    test_false_19_commune_completion_fails_closed_even_rehashed()
    test_opened_runtime_authorization_fails_closed_even_rehashed()
    print("ROAD_MUNICIPALITY_AUDIT_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
