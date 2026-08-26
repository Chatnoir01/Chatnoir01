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
assert review["source_evidence"]["lock_path"] == "data/provenance/anneessens_urbis_source_cell.measurement.json"
assert review["source_evidence"]["persistence_contract_path"] == "data/qa/anneessens_urbis_source_cell.persistence.contract.json"
assert review["source_evidence"]["authority"] == "Paradigm / Brussels-Capital Region"
assert review["source_evidence"]["license"] == "CC0-1.0"
assert review["source_evidence"]["source_semantic_sha256"] == mod.SOURCE_SEMANTIC_SHA
assert review["source_evidence"]["layer_accounting"] == mod.EXPECTED_COUNTS
assert review["source_evidence"]["building_ownership"] == {"ownership_filtered": 52, "invalid_ownership_features": 0}
assert review["municipality_boundary"]["assignment_policy"] == "retain_all_official_intersections_no_dominant_municipality_canonicalization"
assert [row["niscode"] for row in review["municipality_boundary"]["intersections"]] == ["21013", "21001", "21004"]
assert abs(sum(row["coverage_ratio"] for row in review["municipality_boundary"]["intersections"]) - 1.0) < 1e-12
assert candidate["provenance"]["municipality_assignment_policy"] == "retain_all_official_intersections_no_dominant_municipality_canonicalization"
assert [row["niscode"] for row in candidate["provenance"]["municipality_intersections"]] == ["21013", "21001", "21004"]
assert all(value is False for value in candidate["maturity"]["gates"].values())
assert all(value is False for value in review["authorization"].values())
assert json.loads(candidate_bytes)["cell_id"] == "bxl-e147500-n169500-s500"
measurement, persistence = mod.validate_source_evidence(
    ROOT,
    json.loads((ROOT / "data/provenance/anneessens_canonical_registration.review.json").read_text()),
)
assert measurement["schema"] == "grand-bruxelles-urbis-source-cell-semantic-measurement-v1"
assert persistence["status"] == "LOCKED_EXACT_SOURCE_ONLY_PERSISTED"
assert persistence["authorization"]["source_persistence"] is True
assert all(
    persistence["authorization"][key] is False
    for key in (
        "source_registration", "canonical_registration", "municipality_assignment",
        "road_to_cell_mapping", "runtime_directory_scan", "runtime_mount",
        "rendered_geometry", "collision", "safe_spawn", "jouable_promotion",
    )
)
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
print("ANNEESSENS_CANONICAL_MANIFEST_CANDIDATE_REGRESSIONS_OK split_source_evidence=true rails_closed=true")