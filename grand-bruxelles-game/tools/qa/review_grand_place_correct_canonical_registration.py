#!/usr/bin/env python3
"""Fail-closed canonical-registration preflight for the corrected Grand-Place source cell.

This tool performs evidence review only. It does not create a canonical manifest, mutate the
registered-cell index, authorize runtime mounting, or contact a remote source.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

TARGET = "bxl-e148500-n170500-s500"
CELL_DIR = Path("data/urbis/remaining_brussels/cells") / TARGET
RAW_KEYS = {
    "buildings": "raw/buildings.geojson",
    "street_axes": "raw/street_axes.geojson",
    "street_surfaces": "raw/street_surfaces.geojson",
    "train_network": "raw/train_network.geojson",
    "tram_network": "raw/tram_network.geojson",
}
CLOSED = [
    "source_registration", "canonical_registration", "municipality_assignment",
    "road_to_cell_mapping", "runtime_directory_scan", "runtime_mount",
    "rendered_geometry", "collision", "safe_spawn", "jouable_promotion",
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_sha(value: object) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return sha256_bytes(payload)


def require_closed_flags(value: dict, *, suffix: str = "_authorized") -> None:
    for key, state in value.items():
        if key.endswith(suffix) and state is not False:
            raise AssertionError(f"authorization unexpectedly open: {key}={state!r}")


def review(repo_root: Path, contract_path: Path, production_base_sha: str) -> dict:
    contract = read_json(repo_root / contract_path)
    assert contract["production_base_sha"] == production_base_sha, "production base drift"
    assert contract["target"] == {
        "cell_id": TARGET,
        "crs": "EPSG:31370",
        "bbox": [148500.0, 170500.0, 149000.0, 171000.0],
    }
    for key in CLOSED:
        assert contract["authorization"][key] is False, f"contract rail opened: {key}"

    source = contract["source_evidence"]
    assert source["authority"] == "Paradigm / Brussels-Capital Region"
    assert source["license"] == "CC0-1.0"
    source_measurement = read_json(repo_root / source["measurement_path"])
    assert source_measurement["cell_id"] == TARGET
    assert source_measurement["crs"] == "EPSG:31370"
    assert source_measurement["bbox"] == contract["target"]["bbox"]
    assert source_measurement["source_semantic_sha256"] == source["source_semantic_sha256"]
    assert source_measurement["manifest_sha256"] == source["manifest_sha256"]
    assert source_measurement["maturity_sha256"] == source["maturity_sha256"]
    assert source_measurement["registration_authorized"] is False
    assert source_measurement["runtime_mount_authorized"] is False
    assert source_measurement["rendered_geometry_authorized"] is False
    assert source_measurement["collision_authorized"] is False
    assert source_measurement["safe_spawn_authorized"] is False
    assert source_measurement["jouable_promotion_authorized"] is False

    cell = repo_root / CELL_DIR
    manifest_path = cell / "manifest.json"
    maturity_path = cell / "maturity.json"
    manifest_bytes = manifest_path.read_bytes()
    maturity_bytes = maturity_path.read_bytes()
    assert sha256_bytes(manifest_bytes) == source["manifest_sha256"], "source manifest bytes drifted"
    assert sha256_bytes(maturity_bytes) == source["maturity_sha256"], "source maturity bytes drifted"
    manifest = json.loads(manifest_bytes)
    maturity = json.loads(maturity_bytes)
    assert manifest["cell_id"] == TARGET and manifest["crs"] == "EPSG:31370"
    assert manifest["bbox"] == contract["target"]["bbox"]
    assert manifest["promotion"] == "source_only_no_runtime_mutation"
    assert maturity["cell_id"] == TARGET and maturity["crs"] == "EPSG:31370"
    assert maturity["maturity"]["state"] == "data_ready"
    gates = maturity["maturity"]["gates"]
    for gate in ["runtime_geometry", "collisions", "streaming", "terrain", "heights", "photo_match", "performance"]:
        assert gates[gate] is False, f"maturity gate unexpectedly open: {gate}"

    observed_counts = {}
    raw_hashes = {}
    for key, relative in RAW_KEYS.items():
        layer = manifest["layers"][key]
        assert layer["file"] == relative
        payload = (cell / relative).read_bytes()
        raw_hashes[key] = sha256_bytes(payload)
        geojson = json.loads(payload)
        assert geojson["type"] == "FeatureCollection"
        observed_counts[key] = len(geojson["features"])
        assert observed_counts[key] == source["layer_counts"][key], f"feature count drifted: {key}"
        measured = source_measurement["layers"][key]
        assert raw_hashes[key] == measured["raw_forensic_sha256"], f"raw bytes drifted: {key}"
        assert observed_counts[key] == measured["features"]
    assert manifest["layers"]["buildings"]["ownership_filtered"] == source["buildings_ownership_filtered"]
    assert manifest["layers"]["buildings"]["invalid_ownership_features"] == source["buildings_invalid_ownership"] == 0

    municipality = contract["municipality_evidence"]
    municipality_measurement = read_json(repo_root / municipality["measurement_path"])
    assert municipality_measurement["semantic_sha256"] == municipality["semantic_sha256"]
    assert municipality_measurement["status"] == municipality["status"] == "MUNICIPALITY_PROVEN_SINGLE"
    coverage = municipality_measurement["municipality_coverage"]
    assert coverage["municipality_id"] == municipality["municipality_id"]
    assert coverage["municipality_niscode"] == municipality["niscode"] == "21004"
    assert coverage["coverage_ratio"] == municipality["coverage_ratio"] == 1.0
    assert coverage["intersection_coverage_sum"] == 1.0
    assert len(coverage["intersections"]) == 1
    for key in [
        "source_registration_authorized", "canonical_registration_authorized",
        "municipality_assignment_authorized", "road_cell_mapping_authorized",
        "runtime_directory_scan_authorized", "runtime_mount_authorized",
        "rendered_geometry_authorized", "collision_authorized",
        "safe_spawn_authorized", "jouable_promotion_authorized",
    ]:
        assert municipality_measurement[key] is False, f"municipality rail opened: {key}"

    index = read_json(repo_root / contract["registered_cell_index"]["path"])
    assert index["schema"] == "grand-bruxelles-registered-cell-manifest-index-v1"
    require_closed_flags(index)
    registered_ids = [entry["cell_id"] for entry in index["entries"]]
    assert len(registered_ids) == index["registered_cell_count"]
    assert len(registered_ids) == len(set(registered_ids)), "duplicate registered cell"
    assert TARGET not in registered_ids, "target is already registered; review phase must stop"

    result = {
        "schema": "grand-bruxelles-grand-place-correct-canonical-registration-review-v1",
        "status": "READY_FOR_CANONICAL_MANIFEST_REVIEW",
        "production_base_sha": production_base_sha,
        "target": contract["target"],
        "source_evidence": {
            "authority": source["authority"],
            "license": source["license"],
            "source_semantic_sha256": source["source_semantic_sha256"],
            "manifest_sha256": source["manifest_sha256"],
            "maturity_sha256": source["maturity_sha256"],
            "layer_counts": observed_counts,
            "raw_sha256": raw_hashes,
            "buildings_ownership_filtered": source["buildings_ownership_filtered"],
            "buildings_invalid_ownership": source["buildings_invalid_ownership"],
        },
        "municipality_evidence": {
            "status": municipality["status"],
            "semantic_sha256": municipality["semantic_sha256"],
            "municipality_id": municipality["municipality_id"],
            "niscode": municipality["niscode"],
            "coverage_ratio": municipality["coverage_ratio"],
        },
        "registered_cell_index": {
            "registered_cell_count": index["registered_cell_count"],
            "semantic_sha256": index["semantic_sha256"],
            "target_present": False,
        },
        "destination_readiness": "SOURCE_CELL_PROVEN_NOT_REGISTERED",
        "registration_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_directory_scan_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    result["semantic_sha256"] = canonical_sha(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = review(args.repo_root, args.contract, args.production_base_sha)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "GRAND_PLACE_CORRECT_CANONICAL_REVIEW_OK "
        f"status={result['status']} semantic={result['semantic_sha256']} "
        f"registered={result['registered_cell_index']['registered_cell_count']} target_present=false rails_closed=true"
    )


if __name__ == "__main__":
    main()
