#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "tools/qa/build_bourse_canonical_manifest_candidate.py"
LOCK = ROOT / "data/provenance/bourse_canonical_manifest_candidate.review.json"
CANONICAL = ROOT / "data/cell_manifests/bxl-e147500-n170000-s500.json"
INDEX = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"
spec = importlib.util.spec_from_file_location("bourse_candidate", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

locked_review = json.loads(LOCK.read_text(encoding="utf-8"))
assert locked_review["status"] == "CANDIDATE_MEASURED_UNREGISTERED"
assert locked_review["candidate_manifest"]["sha256"] == "ee8fca94ca0e2a9b98e20df10e894ccf0407b82ec7be84c5b103be5f46222af4"
assert locked_review["semantic_sha256"] == "dfb707ba5dee41c0cc7a204751ddf229eba3944c389c92629d098634e7ff5ad8"
assert [r["niscode"] for r in locked_review["municipality_boundary"]["intersections"]] == ["21001", "21004"]
assert all(value is False for value in locked_review["authorization"].values())

if CANONICAL.exists():
    # Post-registration phase: the historical candidate remains immutable evidence.
    # Validate the registered manifest/index binding instead of attempting to recreate
    # an unregistered state that no longer exists.
    canonical = json.loads(CANONICAL.read_text(encoding="utf-8"))
    assert canonical["format"] == "grand-bruxelles-cell-maturity-v1"
    assert canonical["cell_id"] == "bxl-e147500-n170000-s500"
    assert canonical["crs"] == "EPSG:31370"
    assert canonical["bbox"] == [147500.0, 170000.0, 148000.0, 170500.0]
    assert canonical["maturity"]["state"] == "data_ready"
    assert all(value is False for value in canonical["maturity"]["gates"].values())
    provenance = canonical["provenance"]
    assert provenance["municipality_assignment_policy"] == "retain_all_official_intersections_no_dominant_municipality_canonicalization"
    assert [r["niscode"] for r in provenance["municipality_intersections"]] == ["21001", "21004"]
    assert provenance["municipality_boundary_semantic_sha256"] == mod.BOUNDARY_SEMANTIC_SHA
    assert provenance["source_semantic_sha256"] == mod.SOURCE_SEMANTIC_SHA

    index = json.loads(INDEX.read_text(encoding="utf-8"))
    rows = [row for row in index["entries"] if row["cell_id"] == mod.CELL_ID]
    assert len(rows) == 1
    row = rows[0]
    assert row["manifest_path"] == "data/cell_manifests/bxl-e147500-n170000-s500.json"
    assert row["maturity_state"] == "data_ready"
    assert row["evidence_only"] is True
    for key in [
        "runtime_directory_scan_authorized", "road_crosswalk_authorized", "runtime_mount_authorized",
        "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ]:
        assert index[key] is False, key
    print("BOURSE_CANONICAL_MANIFEST_CANDIDATE_POST_REGISTRATION_INTEGRITY_OK")
else:
    locked_base = str(locked_review["production_base_sha"])
    review, candidate, candidate_bytes = mod.build(ROOT, locked_base)
    assert review["production_base_sha"] == locked_base
    assert review["status"] == "CANDIDATE_MEASURED_UNREGISTERED"
    assert review["target"]["cell_id"] == "bxl-e147500-n170000-s500"
    assert review["registered_cell_index"]["registered_cell_count"] == 2
    assert review["registered_cell_index"]["target_registered"] is False
    assert review["municipality_boundary"]["assignment_policy"] == "retain_all_official_intersections_no_dominant_municipality_canonicalization"
    assert [row["niscode"] for row in review["municipality_boundary"]["intersections"]] == ["21001", "21004"]
    assert abs(sum(row["coverage_ratio"] for row in review["municipality_boundary"]["intersections"]) - 1.0) < 1e-12
    assert candidate["provenance"]["municipality_assignment_policy"] == "retain_all_official_intersections_no_dominant_municipality_canonicalization"
    assert [row["niscode"] for row in candidate["provenance"]["municipality_intersections"]] == ["21001", "21004"]
    assert all(value is False for value in candidate["maturity"]["gates"].values())
    assert all(value is False for value in review["authorization"].values())
    assert json.loads(candidate_bytes)["cell_id"] == "bxl-e147500-n170000-s500"

bad = {
    "semantic_sha256": mod.BOUNDARY_SEMANTIC_SHA,
    "automatic_municipality_assignment_authorized": False,
    "intersections": [mod.EXPECTED_INTERSECTIONS[0]],
}
try:
    mod.validate_boundary(bad)
except RuntimeError:
    pass
else:
    raise AssertionError("dominant-municipality shortcut was not rejected")

bad = {
    "semantic_sha256": mod.BOUNDARY_SEMANTIC_SHA,
    "automatic_municipality_assignment_authorized": True,
    "intersections": mod.EXPECTED_INTERSECTIONS,
}
try:
    mod.validate_boundary(bad)
except RuntimeError:
    pass
else:
    raise AssertionError("automatic municipality assignment widening was not rejected")

print("BOURSE_CANONICAL_MANIFEST_CANDIDATE_REGRESSIONS_OK")
