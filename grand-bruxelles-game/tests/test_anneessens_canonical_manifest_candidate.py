#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "tools/qa/build_anneessens_canonical_manifest_candidate.py"
spec = importlib.util.spec_from_file_location("anneessens_candidate", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
review, candidate, candidate_bytes = mod.build(ROOT, "0" * 40)
assert review["status"] == "CANDIDATE_MEASURED_UNREGISTERED"
assert review["target"]["cell_id"] == "bxl-e147500-n169500-s500"
assert review["registered_cell_index"]["registered_cell_count"] == 4
assert review["registered_cell_index"]["target_registered"] is False
assert review["municipality_boundary"]["assignment_policy"] == "retain_all_official_intersections_no_dominant_municipality_canonicalization"
assert [row["niscode"] for row in review["municipality_boundary"]["intersections"]] == ["21013", "21001", "21004"]
assert abs(sum(row["coverage_ratio"] for row in review["municipality_boundary"]["intersections"]) - 1.0) < 1e-12
assert candidate["provenance"]["municipality_assignment_policy"] == "retain_all_official_intersections_no_dominant_municipality_canonicalization"
assert [row["niscode"] for row in candidate["provenance"]["municipality_intersections"]] == ["21013", "21001", "21004"]
assert all(value is False for value in candidate["maturity"]["gates"].values())
assert all(value is False for value in review["authorization"].values())
assert json.loads(candidate_bytes)["cell_id"] == "bxl-e147500-n169500-s500"
boundary = {"status": "HOLD_MUNICIPALITY_BOUNDARY_CELL","semantic_sha256": mod.BOUNDARY_SEMANTIC_SHA,"assignment_policy": "retain_all_official_intersections_no_dominant_municipality_canonicalization","coverage_sum": 1.0,"intersections": [{"niscode": "21013","inspire_id": "https://databrussels.be/id/municipality/5000083","coverage_ratio": 1.0}]}
try:
    mod.validate_boundary(boundary)
except RuntimeError:
    pass
else:
    raise AssertionError("dominant-municipality shortcut was not rejected")
boundary = json.loads((ROOT / "data/provenance/anneessens_canonical_registration.review.json").read_text())["municipality_boundary"]
bad = json.loads(json.dumps(boundary)); bad["intersections"] = list(reversed(bad["intersections"]))
try:
    mod.validate_boundary(bad)
except RuntimeError:
    pass
else:
    raise AssertionError("municipality order drift was not rejected")
print("ANNEESSENS_CANONICAL_MANIFEST_CANDIDATE_REGRESSIONS_OK")
