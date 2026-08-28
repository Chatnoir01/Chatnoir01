#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_acquisition_frontier.py"
spec = importlib.util.spec_from_file_location("road_acquisition_frontier", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def paths():
    return (
        ROOT / "data" / "osm",
        ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json",
        ROOT / "tools" / "build_road_destination_catalog.py",
        ROOT / "tools" / "build_road_destination_provenance_binding.py",
        ROOT / "tools" / "build_road_municipality_coverage_audit.py",
    )


def build_real():
    return module.build_frontier(*paths())


def validate_real(frontier):
    module.validate_frontier(frontier, *paths())


def rehash(frontier):
    unsigned = dict(frontier)
    unsigned.pop("frontier_sha256", None)
    frontier["frontier_sha256"] = module.sha256_json(unsigned)


def test_real_frontier_is_deterministic_source_locked_and_closed() -> None:
    first = build_real()
    second = build_real()
    validate_real(first)
    validate_real(second)
    assert module.canonical_json(first) == module.canonical_json(second)
    assert first["source_entry_count"] == 139
    assert first["registered_not_rendered_count"] == 96
    assert first["acquisition_candidate_count"] == 43
    assert len(first["candidates"]) == 43
    assert first["assignment_policy"] == "NO_INFERENCE_SOURCE_EVIDENCE_REQUIRED"
    assert first["automatic_registration_claimed"] is False
    for row in first["candidates"]:
        assert row["state"] == "DISCOVERED"
        assert row["cell_id"] is None
        assert row["municipalities"] is None
        assert row["proposed_cell_id"] is None
        assert row["proposed_municipality_niscodes"] is None
        assert row["required_evidence"] == [
            "exact_source_geometry_identity",
            "source_backed_epsg31370_cell_intersection",
            "locked_cell_manifest_identity",
            "explicit_municipality_provenance",
        ]
    auth = first["authorization"]
    for key in (
        "source_registration_authorized",
        "road_cell_mapping_authorized",
        "render_authorized",
        "collision_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "jouable_authorized",
    ):
        assert auth[key] is False


def test_rehashed_inferred_cell_assignment_fails_closed() -> None:
    frontier = build_real()
    frontier["candidates"][0]["proposed_cell_id"] = "bxl-e147500-n169500-s500"
    rehash(frontier)
    try:
        validate_real(frontier)
    except SystemExit as exc:
        assert "inferred assignment" in str(exc) or "source binding drift" in str(exc)
    else:
        raise AssertionError("rehashed inferred cell assignment did not fail closed")


def test_rehashed_inferred_municipality_assignment_fails_closed() -> None:
    frontier = build_real()
    frontier["candidates"][0]["proposed_municipality_niscodes"] = ["21004"]
    rehash(frontier)
    try:
        validate_real(frontier)
    except SystemExit as exc:
        assert "inferred assignment" in str(exc) or "source binding drift" in str(exc)
    else:
        raise AssertionError("rehashed inferred municipality assignment did not fail closed")


def test_rehashed_candidate_identity_substitution_fails_closed() -> None:
    frontier = build_real()
    frontier["candidates"][0]["road_osm_id"] += 1
    rehash(frontier)
    try:
        validate_real(frontier)
    except SystemExit as exc:
        assert "source binding drift" in str(exc) or "candidate identity drift" in str(exc)
    else:
        raise AssertionError("rehashed road identity substitution did not fail closed")


def test_opened_runtime_authorization_fails_closed_even_rehashed() -> None:
    frontier = build_real()
    frontier["authorization"]["runtime_mount_authorized"] = True
    rehash(frontier)
    try:
        validate_real(frontier)
    except SystemExit as exc:
        assert "opened runtime_mount_authorized" in str(exc)
    else:
        raise AssertionError("opened runtime authorization did not fail closed")


def main() -> int:
    test_real_frontier_is_deterministic_source_locked_and_closed()
    test_rehashed_inferred_cell_assignment_fails_closed()
    test_rehashed_inferred_municipality_assignment_fails_closed()
    test_rehashed_candidate_identity_substitution_fails_closed()
    test_opened_runtime_authorization_fails_closed_even_rehashed()
    print("ROAD_ACQUISITION_FRONTIER_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
