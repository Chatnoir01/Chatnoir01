from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "data/provenance/brussels_mobility_sidewalk_source.json"
MANIFEST_PATH = ROOT / "data/provenance/brussels_mobility_sidewalk_corridor_snapshot_manifest.json"

EXPECTED_PRODUCTION_BASE = "d0ffc87f88d851298feabea67d52192929ff49cb"
EXPECTED_SOURCE_LOCK_SHA = "078befc176f26f0ece55cad3a2fdc3c79f1e700c"
EXPECTED_FEATURE_COUNT = 3158
EXPECTED_FEATURE_ID_SHA256 = "779f6fdac205ebf3ebfa99dd360f992e5b13682a99f05a27858405bb34fe5fb8"
EXPECTED_CANONICAL_SHA256 = "fff46be67855b1d2e651e735397e970550513e4e657bda3b3f09cc285b30b3dc"
EXPECTED_DOMAIN_SHA256 = "7c6fcec4a5b8add262e127bb0097350928450ebb2fe01aa96c63025e627cdc79"
EXPECTED_ARTIFACT_DIGEST = "sha256:d48565b26e2b5c7893b5deb554d49ae2cca26ed8eb61434c63ae712cc1068dc6"
EXPECTED_COUNTS = {"A": 12, "AC": 2, "C": 26, "G": 12, "I": 1337, "IC": 55, "K": 22, "M": 96, "O": 1, "S": 1554, "SC": 7, "W": 34}


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_snapshot_manifest_matches_merged_source_lock() -> None:
    source = _load(SOURCE_PATH)
    manifest = _load(MANIFEST_PATH)

    assert manifest["schema"] == "grand-bruxelles-official-sidewalk-corridor-snapshot-manifest-v1"
    assert manifest["production_base_sha"] == EXPECTED_PRODUCTION_BASE
    assert manifest["source_lock_merge_pr"] == 1146
    assert manifest["source_lock_merge_sha"] == EXPECTED_SOURCE_LOCK_SHA

    source_identity = source["source"]
    manifest_identity = manifest["source"]
    for key in ("publisher", "dataset", "layer", "license", "crs"):
        assert manifest_identity[key] == source_identity[key]
    assert manifest_identity["query_bbox"] == [147650.0, 169300.0, 149100.0, 171050.0]
    assert manifest_identity["ssft_filter_applied"] is False

    locked = source["required_corridor_extract"]["validated_snapshot"]
    persisted = manifest["validated_snapshot"]
    assert persisted["feature_count"] == locked["feature_count"] == EXPECTED_FEATURE_COUNT
    assert persisted["feature_id_sha256"] == locked["feature_id_sha256"] == EXPECTED_FEATURE_ID_SHA256
    assert persisted["canonical_source_content_sha256"] == locked["canonical_source_content_sha256"] == EXPECTED_CANONICAL_SHA256
    assert persisted["attribute_domain_sha256"] == locked["attribute_domain_sha256"] == EXPECTED_DOMAIN_SHA256
    assert persisted["ssft_counts"] == locked["ssft_counts"] == EXPECTED_COUNTS
    assert sum(persisted["ssft_counts"].values()) == EXPECTED_FEATURE_COUNT


def test_snapshot_manifest_is_evidence_not_runtime_authorization() -> None:
    manifest = _load(MANIFEST_PATH)
    policy = manifest["policy"]
    claims = manifest["claims"]
    evidence = manifest["acquisition_evidence"]

    assert evidence["workflow_run_id"] == 32584912488
    assert evidence["artifact_id"] == 9478782615
    assert evidence["artifact_digest"] == EXPECTED_ARTIFACT_DIGEST
    assert evidence["raw_source_digest_is_stability_authority"] is False

    assert claims["horizontal_sidewalk_geometry_source_backed"] is True
    assert claims["official_feature_identity_source_backed"] is True
    assert claims["ssft_values_source_backed"] is True
    assert claims["curb_height_source_backed"] is False
    assert claims["surface_elevation_source_backed"] is False
    assert claims["sidewalk_profile_source_backed"] is False
    assert claims["paving_unit_dimensions_source_backed"] is False
    assert claims["material_identity_source_backed"] is False

    assert policy["manifest_is_geometry_payload"] is False
    assert policy["canonical_geometry_payload_persisted"] is False
    assert policy["runtime_geometry_authorized"] is False
    assert policy["jouable_promotion_authorized"] is False
    assert policy["vertical_extrusion_allowed"] is False
    assert policy["curb_height_inference_allowed"] is False
    assert policy["overlap_measurement_required_before_runtime"] is True
    assert policy["overlap_measurement_authorizes_runtime"] is False

    next_gate = manifest["next_gate"]
    assert next_gate["persist_exact_canonical_geometry_payload"] is True
    assert next_gate["measure_horizontal_overlap_against_generic_sidewalks"] is True
    assert next_gate["generic_sidewalk_count_reference"] == 430
    assert next_gate["runtime_replacement_forbidden_until_gate_green"] is True
