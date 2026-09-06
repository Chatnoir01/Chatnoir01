from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools/city_machine"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from build_road_destination_factory_catalog import build_catalog

REGISTRY = ROOT / "data/source_plans/brussels_missing_road_source_registry.json"
EVIDENCE = ROOT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
CATALOG = ROOT / "data/source_plans/brussels_road_destination_factory_catalog.lock.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def test_locked_catalog_is_exact_deterministic_derivation():
    generated = build_catalog(load(REGISTRY), load(EVIDENCE))
    assert generated == load(CATALOG)
    assert generated["accounting"] == {
        "expected_municipalities": 16,
        "acquired_artifact_locked": 7,
        "remote_acquisition_unresolved": 9,
        "road_identity_materialized": 0,
        "cell_assignment_materialized": 0,
    }
    assert all(row["source_file"] is None for row in generated["municipalities"])
    assert all(row["registration_authorized"] is False for row in generated["municipalities"])
    assert all(row["render_authorized"] is False for row in generated["municipalities"])
    assert all(row["collision_authorized"] is False for row in generated["municipalities"])
    assert all(row["runtime_ready"] is False for row in generated["municipalities"])
    assert all(row["jouable"] is False for row in generated["municipalities"])


def test_derivation_rejects_registry_evidence_identity_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["unresolved_acquisitions"][0]["osm_relation_id"] += 1
    with pytest.raises(SystemExit, match="identity drift"):
        build_catalog(registry, mutated)


def test_derivation_rejects_partition_overlap():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    duplicate = copy.deepcopy(mutated["successful_acquisitions"][0])
    duplicate.pop("artifact")
    duplicate.pop("authorization")
    duplicate.pop("osm_base_timestamp")
    duplicate.pop("road_count")
    duplicate.pop("point_count")
    duplicate.pop("bounds_m")
    duplicate.pop("raw_snapshot_semantic_sha256")
    duplicate.pop("normalized_game_source_semantic_sha256")
    duplicate["status"] = "REMOTE_ACQUISITION_UNRESOLVED"
    mutated["unresolved_acquisitions"].append(duplicate)
    mutated["accounting"]["unresolved_acquisitions"] += 1
    mutated["accounting"]["expected_municipalities"] += 1
    with pytest.raises(SystemExit, match="partitions overlap"):
        build_catalog(registry, mutated)


def test_derivation_rejects_opened_downstream_authorization():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["successful_acquisitions"][0]["authorization"]["render_authorized"] = True
    with pytest.raises(SystemExit, match="downstream authorization opened"):
        build_catalog(registry, mutated)


def test_derivation_rejects_registry_opened_downstream_authorization():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(registry)
    mutated["authorization"]["source_registration_authorized"] = True
    with pytest.raises(SystemExit, match="registry downstream authorization opened"):
        build_catalog(mutated, evidence)


def test_derivation_rejects_unresolved_row_schema_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["unresolved_acquisitions"][0]["authorization"] = {"render_authorized": True}
    with pytest.raises(SystemExit, match="unresolved acquisition schema drift"):
        build_catalog(registry, mutated)


def test_derivation_rejects_locked_row_schema_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["successful_acquisitions"][0]["source_file"] = "unlocked.json"
    with pytest.raises(SystemExit, match="locked acquisition schema drift"):
        build_catalog(registry, mutated)


def test_derivation_rejects_registry_municipality_schema_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(registry)
    mutated["municipalities"][0]["source_file"] = "unlocked.json"
    with pytest.raises(SystemExit, match="registry municipality schema drift"):
        build_catalog(mutated, evidence)


def test_derivation_rejects_registry_root_schema_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(registry)
    mutated["runtime_ready"] = True
    with pytest.raises(SystemExit, match="registry root schema drift"):
        build_catalog(mutated, evidence)


def test_derivation_rejects_evidence_root_schema_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["registered"] = True
    with pytest.raises(SystemExit, match="evidence root schema drift"):
        build_catalog(registry, mutated)


def test_derivation_rejects_locked_artifact_schema_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["successful_acquisitions"][0]["artifact"]["source_file"] = "unlocked.json"
    with pytest.raises(SystemExit, match="locked artifact schema drift"):
        build_catalog(registry, mutated)


def test_derivation_rejects_locked_artifact_invalid_identity_fields():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["successful_acquisitions"][0]["artifact"]["id"] = True
    with pytest.raises(SystemExit, match="invalid locked artifact"):
        build_catalog(registry, mutated)


def test_derivation_rejects_common_source_provenance_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["source"]["license"] = "UNKNOWN"
    with pytest.raises(SystemExit, match="source provenance drift"):
        build_catalog(registry, mutated)


def test_derivation_rejects_evidence_query_contract_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["source"]["query_scope"] = "bounding_box"
    with pytest.raises(SystemExit, match="evidence source contract drift"):
        build_catalog(registry, mutated)


def test_derivation_rejects_game_frame_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["game_frame"]["origin_lon"] += 0.001
    with pytest.raises(SystemExit, match="game frame drift"):
        build_catalog(registry, mutated)


def test_derivation_rejects_source_schema_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(registry)
    mutated["source"]["runtime_ready"] = True
    with pytest.raises(SystemExit, match="registry source schema drift"):
        build_catalog(mutated, evidence)


def test_derivation_rejects_locked_evidence_bool_counts():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["successful_acquisitions"][0]["road_count"] = True
    with pytest.raises(SystemExit, match="invalid locked source evidence"):
        build_catalog(registry, mutated)


def test_derivation_rejects_locked_evidence_degenerate_bounds():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["successful_acquisitions"][0]["bounds_m"] = [10.0, 20.0, 10.0, 30.0]
    with pytest.raises(SystemExit, match="invalid locked source evidence"):
        build_catalog(registry, mutated)


def test_derivation_rejects_locked_evidence_invalid_semantic_hash():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["successful_acquisitions"][0]["normalized_game_source_semantic_sha256"] = "NOT-A-SHA"
    with pytest.raises(SystemExit, match="invalid locked source evidence"):
        build_catalog(registry, mutated)
