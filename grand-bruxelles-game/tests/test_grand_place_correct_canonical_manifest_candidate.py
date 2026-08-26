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

print("GRAND_PLACE_CORRECT_CANONICAL_MANIFEST_CANDIDATE_REGRESSIONS_OK")
