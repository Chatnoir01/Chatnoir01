#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "tools/qa/build_bourse_canonical_manifest_candidate.py"
LOCK = ROOT / "data/provenance/bourse_canonical_manifest_candidate.review.json"
spec = importlib.util.spec_from_file_location("bourse_candidate", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

locked_review = json.loads(LOCK.read_text(encoding="utf-8"))
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
