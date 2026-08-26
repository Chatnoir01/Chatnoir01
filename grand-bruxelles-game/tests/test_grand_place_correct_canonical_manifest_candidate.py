#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "tools/qa/build_grand_place_correct_canonical_manifest_candidate.py"
spec = importlib.util.spec_from_file_location("grand_place_correct_candidate", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

preflight = json.loads((ROOT / mod.PREFLIGHT_PATH).read_text(encoding="utf-8"))
municipality = mod.validate_preflight(preflight)
assert municipality["status"] == "MUNICIPALITY_PROVEN_SINGLE"
assert municipality["municipality_id"] == mod.MUNICIPALITY_ID
assert str(municipality["niscode"]) == mod.MUNICIPALITY_NIS
assert municipality["coverage_ratio"] == 1.0

canonical_path = ROOT / "data/cell_manifests" / f"{mod.CELL_ID}.json"
locked_path = ROOT / "data/provenance/grand_place_correct_canonical_manifest_candidate.review.json"
index_path = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"

if canonical_path.is_file():
    review = json.loads(locked_path.read_text(encoding="utf-8"))
    canonical = json.loads(canonical_path.read_text(encoding="utf-8"))
    index = json.loads(index_path.read_text(encoding="utf-8"))
    assert review["status"] == "CANDIDATE_MEASURED_UNREGISTERED"
    assert review["target"]["cell_id"] == mod.CELL_ID
    assert review["municipality_evidence"]["niscode"] == "21004"
    assert review["municipality_evidence"]["coverage_ratio"] == 1.0
    assert all(value is False for value in review["authorization"].values())
    assert canonical["cell_id"] == mod.CELL_ID
    assert canonical["crs"] == "EPSG:31370"
    assert canonical["provenance"]["municipality_niscode"] == "21004"
    assert canonical["provenance"]["municipality_coverage_ratio"] == 1.0
    assert canonical["provenance"]["municipality_id"] == mod.MUNICIPALITY_ID
    assert all(value is False for value in canonical["maturity"]["gates"].values())
    rows = {row["cell_id"]: row for row in index["entries"]}
    row = rows[mod.CELL_ID]
    assert row["evidence_only"] is True
    for key in [
        "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized",
        "safe_spawn_authorized", "jouable_promotion_authorized",
    ]:
        assert row[key] is False, key
    lifecycle = "registered_evidence_only"
else:
    review, candidate, candidate_bytes = mod.build(ROOT, preflight["production_base_sha"])
    assert review["status"] == "CANDIDATE_MEASURED_UNREGISTERED"
    assert review["target"]["cell_id"] == mod.CELL_ID
    assert review["registered_cell_index"]["registered_cell_count"] == 3
    assert review["registered_cell_index"]["target_registered"] is False
    assert review["municipality_evidence"]["niscode"] == "21004"
    assert review["municipality_evidence"]["coverage_ratio"] == 1.0
    assert review["municipality_evidence"]["assignment_policy"] == "single_official_municipality_proven_full_cell_coverage"
    assert candidate["provenance"]["municipality"]["niscode"] == "21004"
    assert candidate["provenance"]["municipality"]["coverage_ratio"] == 1.0
    assert candidate["provenance"]["municipality_assignment_policy"] == "single_official_municipality_proven_full_cell_coverage"
    assert all(value is False for value in candidate["maturity"]["gates"].values())
    assert all(value is False for value in review["authorization"].values())
    assert json.loads(candidate_bytes)["cell_id"] == mod.CELL_ID
    lifecycle = "unregistered_candidate"

bad = copy.deepcopy(preflight)
bad["municipality_evidence"]["niscode"] = "21001"
try:
    mod.validate_preflight(bad)
except RuntimeError:
    pass
else:
    raise AssertionError("municipality identity drift was not rejected")

bad = copy.deepcopy(preflight)
bad["municipality_evidence"]["coverage_ratio"] = 0.999
try:
    mod.validate_preflight(bad)
except RuntimeError:
    pass
else:
    raise AssertionError("partial municipality coverage was not rejected")

bad = copy.deepcopy(preflight)
bad["runtime_mount_authorized"] = True
try:
    mod.validate_preflight(bad)
except RuntimeError:
    pass
else:
    raise AssertionError("runtime authorization widening was not rejected")

print(f"GRAND_PLACE_CORRECT_CANONICAL_MANIFEST_CANDIDATE_REGRESSIONS_OK lifecycle={lifecycle}")
