#!/usr/bin/env python3
"""Measure official municipality coverage for the corrected persisted Grand-Place UrbIS source cell.

Evidence-only. This never registers the source cell and cannot authorize road mapping,
runtime mounting, rendering, collision, safe spawn or JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

CELL_ID = "bxl-e148500-n170500-s500"
GRID_CELL_ID = "E148500_N170500"
CRS = "EPSG:31370"
BBOX = [148500.0, 170500.0, 149000.0, 171000.0]
EXPECTED_SOURCE_SEMANTIC_SHA256 = "683391007df04a6a6c6c597f3d64411e05b206cf8dd41f7aebaf7d8df76a56e3"
EXPECTED_MANIFEST_SHA256 = "f464b35581b9231582daafbd28c07f1b15e3aeae2d7b683385b7073b6b73658f"
EXPECTED_MATURITY_SHA256 = "e5f3eaddc2fba5a5d359f3e47f5819ae3efd7994174ee7c452104d7ea01d95e1"
EXPECTED_LAYER_COUNTS = {"buildings":1110,"street_axes":180,"street_surfaces":598,"train_network":12,"tram_network":12}
CLOSED_MEASUREMENT_RAILS = ("registration_authorized","runtime_mount_authorized","rendered_geometry_authorized","collision_authorized","safe_spawn_authorized","jouable_promotion_authorized")
CLOSED_OUTPUT_RAILS = ("source_registration_authorized","canonical_registration_authorized","municipality_assignment_authorized","road_cell_mapping_authorized","runtime_directory_scan_authorized","runtime_mount_authorized","rendered_geometry_authorized","collision_authorized","safe_spawn_authorized","jouable_promotion_authorized")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _load_module(path: Path):
    spec = importlib.util.spec_from_file_location("road_cell_municipality", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import municipality engine: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_measurement(measurement: dict[str, Any]) -> None:
    if measurement.get("schema") != "grand-bruxelles-urbis-source-cell-semantic-measurement-v1":
        raise RuntimeError("Grand-Place corrected source measurement schema drift")
    if measurement.get("cell_id") != CELL_ID or measurement.get("crs") != CRS:
        raise RuntimeError("Grand-Place corrected source cell identity/CRS drift")
    if [float(v) for v in measurement.get("bbox", [])] != BBOX:
        raise RuntimeError("Grand-Place corrected source bbox drift")
    if measurement.get("maturity_state") != "data_ready":
        raise RuntimeError("Grand-Place corrected source must remain data_ready")
    if measurement.get("source_semantic_sha256") != EXPECTED_SOURCE_SEMANTIC_SHA256:
        raise RuntimeError("Grand-Place corrected source semantic SHA drift")
    if measurement.get("manifest_sha256") != EXPECTED_MANIFEST_SHA256:
        raise RuntimeError("Grand-Place corrected source manifest SHA drift")
    if measurement.get("maturity_sha256") != EXPECTED_MATURITY_SHA256:
        raise RuntimeError("Grand-Place corrected maturity SHA drift")
    layers = measurement.get("layers") or {}
    for name, expected in EXPECTED_LAYER_COUNTS.items():
        if int((layers.get(name) or {}).get("features", -1)) != expected:
            raise RuntimeError(f"Grand-Place corrected {name} count drift")
    buildings = layers.get("buildings") or {}
    if int(buildings.get("ownership_filtered", -1)) != 70:
        raise RuntimeError("Grand-Place corrected building ownership-filter accounting drift")
    if int(buildings.get("invalid_ownership_features", -1)) != 0:
        raise RuntimeError("Grand-Place corrected source contains invalid building ownership")
    for key in CLOSED_MEASUREMENT_RAILS:
        if measurement.get(key) is not False:
            raise RuntimeError(f"Grand-Place corrected source rail {key} must remain false")


def validate_persisted_source(repo_root: Path) -> dict[str, Any]:
    measurement_path = repo_root / "data/provenance/grand_place_correct_urbis_source_cell.measurement.json"
    cell_dir = repo_root / "data/urbis/remaining_brussels/cells" / CELL_ID
    measurement = json.loads(measurement_path.read_text(encoding="utf-8"))
    validate_measurement(measurement)
    manifest_raw = (cell_dir / "manifest.json").read_bytes()
    maturity_raw = (cell_dir / "maturity.json").read_bytes()
    if sha256_bytes(manifest_raw) != EXPECTED_MANIFEST_SHA256:
        raise RuntimeError("persisted Grand-Place corrected manifest bytes drift")
    if sha256_bytes(maturity_raw) != EXPECTED_MATURITY_SHA256:
        raise RuntimeError("persisted Grand-Place corrected maturity bytes drift")
    manifest = json.loads(manifest_raw)
    maturity = json.loads(maturity_raw)
    if manifest.get("cell_id") != CELL_ID or manifest.get("crs") != CRS:
        raise RuntimeError("persisted Grand-Place corrected manifest identity/CRS drift")
    if [float(v) for v in manifest.get("bbox", [])] != BBOX:
        raise RuntimeError("persisted Grand-Place corrected manifest bbox drift")
    if manifest.get("promotion") != "source_only_no_runtime_mutation":
        raise RuntimeError("Grand-Place corrected source promotion contract drift")
    if (maturity.get("maturity") or {}).get("state") != "data_ready":
        raise RuntimeError("persisted Grand-Place corrected maturity state drift")
    gates = (maturity.get("maturity") or {}).get("gates") or {}
    for key in ("runtime_geometry","collisions","streaming","terrain","heights","photo_match","performance"):
        if gates.get(key) is not False:
            raise RuntimeError(f"Grand-Place corrected maturity gate {key} must remain false")
    for name, expected_count in EXPECTED_LAYER_COUNTS.items():
        layer = measurement["layers"][name]
        raw = (cell_dir / str(layer["file"])).read_bytes()
        if len(raw) != int(layer["raw_bytes"]) or sha256_bytes(raw) != layer["raw_forensic_sha256"]:
            raise RuntimeError(f"persisted Grand-Place corrected {name} bytes drift")
        payload = json.loads(raw)
        if not isinstance(payload.get("features"), list) or len(payload["features"]) != expected_count:
            raise RuntimeError(f"persisted Grand-Place corrected {name} feature count drift")
    return measurement


def _semantic_basis(result: dict[str, Any]) -> dict[str, Any]:
    basis = copy.deepcopy(result)
    basis["municipality_source"].pop("raw_payload_sha256", None)
    coverage = basis.get("municipality_coverage") or {}
    coverage.pop("transport_feature_ids", None)
    basis.pop("semantic_sha256", None)
    return basis


def run(repo_root: Path, output_path: Path) -> dict[str, Any]:
    source_measurement = validate_persisted_source(repo_root)
    engine = _load_module(repo_root / "tools/qa/measure_road_cell_municipality_preflight.py")
    municipalities, source_url, raw_sha = engine.fetch_official_municipalities()
    coverage = engine.analyze_municipality_coverage(BBOX, municipalities)
    result: dict[str, Any] = {
        "schema": "grand-bruxelles-grand-place-correct-source-cell-municipality-preflight-v1",
        "status": coverage["status"],
        "cell": {"cell_id":CELL_ID,"grid_cell_id":GRID_CELL_ID,"crs":CRS,"bbox":BBOX},
        "persisted_source": {
            "measurement_path": "data/provenance/grand_place_correct_urbis_source_cell.measurement.json",
            "source_semantic_sha256": source_measurement["source_semantic_sha256"],
            "manifest_sha256": source_measurement["manifest_sha256"],
            "maturity_sha256": source_measurement["maturity_sha256"],
            "layer_counts": {name: source_measurement["layers"][name]["features"] for name in EXPECTED_LAYER_COUNTS},
            "buildings_ownership_filtered": source_measurement["layers"]["buildings"]["ownership_filtered"],
            "buildings_invalid_ownership": source_measurement["layers"]["buildings"]["invalid_ownership_features"],
        },
        "municipality_source": {
            "authority":"Paradigm / Brussels-Capital Region","service":"UrbIS vector WFS","layer":"urbisvector:Municipalities","license":"CC0-1.0","crs":CRS,
            "url":source_url,"feature_count":len(municipalities["features"]),"raw_payload_sha256":raw_sha,
        },
        "municipality_coverage": coverage,
        "source_registration_authorized":False,"canonical_registration_authorized":False,"municipality_assignment_authorized":False,"road_cell_mapping_authorized":False,
        "runtime_directory_scan_authorized":False,"runtime_mount_authorized":False,"rendered_geometry_authorized":False,"collision_authorized":False,"safe_spawn_authorized":False,"jouable_promotion_authorized":False,
    }
    for key in CLOSED_OUTPUT_RAILS:
        if result[key] is not False:
            raise RuntimeError(f"output rail {key} must remain false")
    canonical = json.dumps(_semantic_basis(result), ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    result["semantic_sha256"] = sha256_bytes(canonical)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"GRAND_PLACE_CORRECT_MUNICIPALITY_PREFLIGHT_OK cell={CELL_ID} status={result['status']} municipalities={len(coverage['intersections'])} coverage={coverage['intersection_coverage_sum']:.12f} semantic={result['semantic_sha256']}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run(args.repo_root.resolve(), args.output.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
