#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

TARGET_CELL_ID = "bxl-e148000-n170000-s500"
TARGET_GRID_CELL_ID = "E148000_N170000"
TARGET_BBOX = [148000.0, 170000.0, 148500.0, 170500.0]
EXPECTED_MUNICIPALITY_SEMANTIC_SHA256 = "f425d22f2a4530da40c3acbd951387b2e61eb311497c8ef3b5cbbce54897ffdb"
EXPECTED_MUNICIPALITY_ID = "https://databrussels.be/id/municipality/5000074"
EXPECTED_NIS = "21004"
EXPECTED_REGISTERED_INDEX_SEMANTIC_SHA256 = "606c57c18fac82bcd74b4bb870e37d89ff31c775b3fa57533559c17d7a75de6f"
EXPECTED_SOURCE_MANIFEST_SHA256 = "4c18e124adfbdb230fcd357c444f58c1d532db2812f77d6f97380676f60e00c7"
EXPECTED_SOURCE_DIGEST = "bbee45393ca07d86515f160e6eb9511c624440ccced97dff564b133eeafe7feb"
EXPECTED_SOURCE_LAYER_COUNTS = {
    "buildings": 772,
    "street_axes": 97,
    "street_surfaces": 410,
    "train_network": 28,
    "tram_network": 28,
}
RAILS = [
    "registration_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
]


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_sha(payload: dict[str, Any]) -> str:
    data = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_false(payload: dict[str, Any], label: str) -> None:
    for key in RAILS:
        if payload.get(key) is not False:
            raise RuntimeError(f"{label} must keep {key}=false")


def validate_source_manifest(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise RuntimeError("authoritative UrbIS source-cell manifest missing")
    if file_sha256(path) != EXPECTED_SOURCE_MANIFEST_SHA256:
        raise RuntimeError("authoritative source manifest byte hash drift")
    source = load_json(path)
    if source.get("format") != "grand-bruxelles-urbis-source-cell-v1":
        raise RuntimeError("authoritative source manifest format drift")
    if source.get("cell_id") != TARGET_CELL_ID:
        raise RuntimeError("authoritative source cell id drift")
    if source.get("crs") != "EPSG:31370":
        raise RuntimeError("authoritative source CRS drift")
    if [float(x) for x in source.get("bbox", [])] != TARGET_BBOX:
        raise RuntimeError("authoritative source bbox drift")
    if source.get("promotion") != "source_only_no_runtime_mutation":
        raise RuntimeError("authoritative source promotion drift")
    if source.get("source_digest") != EXPECTED_SOURCE_DIGEST:
        raise RuntimeError("authoritative source digest drift")
    layers = source.get("layers")
    if not isinstance(layers, dict):
        raise RuntimeError("authoritative source layers missing")
    observed = {name: int((layers.get(name) or {}).get("features", -1)) for name in EXPECTED_SOURCE_LAYER_COUNTS}
    if observed != EXPECTED_SOURCE_LAYER_COUNTS:
        raise RuntimeError(f"authoritative source layer accounting drift: {observed!r}")
    buildings = layers.get("buildings") or {}
    if int(buildings.get("ownership_filtered", -1)) != 61:
        raise RuntimeError("authoritative source building ownership-filter accounting drift")
    if int(buildings.get("invalid_ownership_features", -1)) != 0:
        raise RuntimeError("authoritative source invalid ownership accounting drift")
    return source


def review(repo_root: Path, municipality_lock_path: Path) -> dict[str, Any]:
    lock = load_json(municipality_lock_path)
    if lock.get("schema") != "grand-bruxelles-road-cell-municipality-preflight-lock-v3":
        raise RuntimeError("municipality lock schema drift")
    if lock.get("status") != "LOCKED_SOURCE_ONLY_V2_REBOUND":
        raise RuntimeError("municipality lock status drift")
    require_false(lock, "municipality lock")

    stable = lock.get("stable_measurement")
    if not isinstance(stable, dict):
        raise RuntimeError("municipality stable_measurement missing")
    require_false(stable, "municipality stable measurement")
    if stable.get("semantic_sha256") != EXPECTED_MUNICIPALITY_SEMANTIC_SHA256:
        raise RuntimeError("municipality semantic lock drift")

    cell = stable.get("cell") or {}
    if cell.get("grid_cell_id") != TARGET_GRID_CELL_ID:
        raise RuntimeError("Grand-Place grid cell drift")
    if [float(x) for x in cell.get("bbox", [])] != TARGET_BBOX:
        raise RuntimeError("Grand-Place bbox drift")
    if cell.get("road_ids") != [13842686, 684214770] or cell.get("road_count") != 2:
        raise RuntimeError("Grand-Place road accounting drift")
    if cell.get("point_hits") != 9 or cell.get("segment_hits") != 7:
        raise RuntimeError("Grand-Place road hit accounting drift")

    coverage = stable.get("municipality_coverage") or {}
    require_false(coverage, "municipality coverage")
    if coverage.get("status") != "MUNICIPALITY_PROVEN_SINGLE":
        raise RuntimeError("municipality not proven single")
    if coverage.get("municipality_id") != EXPECTED_MUNICIPALITY_ID:
        raise RuntimeError("municipality identity drift")
    if str(coverage.get("municipality_niscode")) != EXPECTED_NIS:
        raise RuntimeError("municipality NIS drift")
    if float(coverage.get("coverage_ratio", -1.0)) != 1.0:
        raise RuntimeError("municipality coverage no longer complete")

    registered_index_path = repo_root / "grand-bruxelles-game/data/provenance/brussels_registered_cell_manifest_index.json"
    registered_index = load_json(registered_index_path)
    if registered_index.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise RuntimeError("registered-cell index schema drift")
    if registered_index.get("semantic_sha256") != EXPECTED_REGISTERED_INDEX_SEMANTIC_SHA256:
        raise RuntimeError("registered-cell index semantic drift")
    for key in [
        "runtime_directory_scan_authorized", "road_crosswalk_authorized", "runtime_mount_authorized",
        "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ]:
        if registered_index.get(key) is not False:
            raise RuntimeError(f"registered-cell index must keep {key}=false")

    registered_ids = [str(entry.get("cell_id")) for entry in registered_index.get("entries", [])]
    if TARGET_CELL_ID in registered_ids:
        raise RuntimeError("Grand-Place target is already registered; this review must not duplicate registration")

    target_manifest = repo_root / f"grand-bruxelles-game/data/cell_manifests/{TARGET_CELL_ID}.json"
    target_source_manifest = repo_root / f"grand-bruxelles-game/data/urbis/remaining_brussels/cells/{TARGET_CELL_ID}/manifest.json"
    target_manifest_present = target_manifest.is_file()
    target_source_manifest_present = target_source_manifest.is_file()
    if target_manifest_present:
        raise RuntimeError("Grand-Place canonical cell manifest appeared without registered-index ownership")

    source = validate_source_manifest(target_source_manifest)

    result: dict[str, Any] = {
        "schema": "grand-bruxelles-grand-place-cell-registration-review-v1",
        "status": "READY_FOR_CANONICAL_MANIFEST_REVIEW",
        "target": {
            "cell_id": TARGET_CELL_ID,
            "grid_cell_id": TARGET_GRID_CELL_ID,
            "crs": "EPSG:31370",
            "bbox": TARGET_BBOX,
            "canonical_manifest_path": f"data/cell_manifests/{TARGET_CELL_ID}.json",
            "authoritative_source_manifest_path": f"data/urbis/remaining_brussels/cells/{TARGET_CELL_ID}/manifest.json",
            "canonical_manifest_present": target_manifest_present,
            "authoritative_source_manifest_present": target_source_manifest_present,
        },
        "municipality_evidence": {
            "lock_path": "data/provenance/grand_place_road_cell_municipality.measurement.json",
            "semantic_sha256": stable["semantic_sha256"],
            "municipality_id": coverage["municipality_id"],
            "municipality_niscode": str(coverage["municipality_niscode"]),
            "coverage_ratio": float(coverage["coverage_ratio"]),
            "road_ids": cell["road_ids"],
            "point_hits": cell["point_hits"],
            "segment_hits": cell["segment_hits"],
        },
        "registered_cell_index": {
            "path": "data/provenance/brussels_registered_cell_manifest_index.json",
            "semantic_sha256": registered_index["semantic_sha256"],
            "registered_cell_count": int(registered_index.get("registered_cell_count", len(registered_ids))),
            "target_already_registered": False,
        },
        "authoritative_source_evidence": {
            "manifest_sha256": file_sha256(target_source_manifest),
            "source_digest": source["source_digest"],
            "format": source["format"],
            "promotion": source["promotion"],
            "layer_feature_counts": {
                name: int(source["layers"][name]["features"])
                for name in EXPECTED_SOURCE_LAYER_COUNTS
            },
            "buildings_ownership_filtered": int(source["layers"]["buildings"]["ownership_filtered"]),
            "buildings_invalid_ownership_features": int(source["layers"]["buildings"]["invalid_ownership_features"]),
        },
        "blocker": "authoritative UrbIS source-cell is present and validated; a separate canonical manifest review may proceed",
        "registration_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    result["semantic_sha256"] = canonical_sha(result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--municipality-lock", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = review(args.repo_root.resolve(), args.municipality_lock.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "GRAND_PLACE_CELL_REGISTRATION_REVIEW: "
        f"status={result['status']} cell={TARGET_CELL_ID} semantic_sha256={result['semantic_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
