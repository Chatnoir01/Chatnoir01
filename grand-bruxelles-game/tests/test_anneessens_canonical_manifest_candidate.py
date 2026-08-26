#!/usr/bin/env python3
from __future__ import annotations
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "tools/qa/build_anneessens_canonical_manifest_candidate.py"
spec = importlib.util.spec_from_file_location("anneessens_candidate", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

TARGET = "bxl-e147500-n169500-s500"
CANONICAL = ROOT / f"data/cell_manifests/{TARGET}.json"
LOCK = ROOT / "data/provenance/anneessens_canonical_manifest_candidate.review.json"
INDEX = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"

# Successor phase: once the separate registration lot writes the canonical
# manifest, the candidate builder must keep refusing to run. The durable gate
# switches from "build an unregistered candidate" to proving that the shipped
# canonical bytes are exactly the previously accepted candidate and that the
# registered-cell index did not open any runtime/JOUABLE rail.
if CANONICAL.exists():
    review = json.loads(LOCK.read_text())
    manifest_bytes = CANONICAL.read_bytes()
    manifest = json.loads(manifest_bytes)
    index = json.loads(INDEX.read_text())

    assert review["status"] == "CANDIDATE_MEASURED_UNREGISTERED"
    assert review["target"]["cell_id"] == TARGET
    assert review["candidate_manifest"]["sha256"] == hashlib.sha256(manifest_bytes).hexdigest()
    assert review["candidate_manifest"]["sha256"] == "3ec056c3c7c8d6ecb6ca5da35a8f6a685fbb14ef9b130065c85cc511b26b7e2a"
    assert manifest["cell_id"] == TARGET
    assert manifest["crs"] == "EPSG:31370"
    assert manifest["provenance"]["municipality_assignment_policy"] == "retain_all_official_intersections_no_dominant_municipality_canonicalization"
    assert [row["niscode"] for row in manifest["provenance"]["municipality_intersections"]] == ["21013", "21001", "21004"]
    assert abs(sum(row["coverage_ratio"] for row in manifest["provenance"]["municipality_intersections"]) - 1.0) < 1e-12
    assert all(value is False for value in manifest["maturity"]["gates"].values())
    assert all(value is False for value in review["authorization"].values())

    assert index["registered_cell_count"] >= 5
    rows = [row for row in index["entries"] if row["cell_id"] == TARGET]
    assert len(rows) == 1
    row = rows[0]
    assert row["manifest_path"] == f"data/cell_manifests/{TARGET}.json"
    assert row["manifest_sha256"] == review["candidate_manifest"]["sha256"]
    assert row["maturity_state"] == "data_ready"
    assert row["evidence_only"] is True
    for key in (
        "runtime_directory_scan_authorized", "road_crosswalk_authorized",
        "runtime_mount_authorized", "rendered_geometry_authorized",
        "collision_authorized", "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ):
        assert index[key] is False, key
    for key in (
        "runtime_mount_authorized", "rendered_geometry_authorized",
        "collision_authorized", "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ):
        assert row[key] is False, key

    try:
        mod.build(ROOT, "0" * 40)
    except RuntimeError as exc:
        assert "canonical Anneessens manifest already exists" in str(exc)
    else:
        raise AssertionError("candidate-only builder must stay fail-closed after registration")

    print("ANNEESSENS_CANONICAL_MANIFEST_SUCCESSOR_REGRESSIONS_OK exact_candidate_bytes=true registered_evidence_only=true rails_closed=true")
    sys.exit(0)

# Pre-registration phase: preserve the original RED-first candidate contract.
review, candidate, candidate_bytes = mod.build(ROOT, "0" * 40)
assert review["status"] == "CANDIDATE_MEASURED_UNREGISTERED"
assert review["target"]["cell_id"] == TARGET
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
assert json.loads(candidate_bytes)["cell_id"] == TARGET
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