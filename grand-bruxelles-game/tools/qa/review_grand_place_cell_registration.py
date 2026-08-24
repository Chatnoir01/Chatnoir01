#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

HISTORICAL_CELL_ID = "bxl-e148000-n170000-s500"
HISTORICAL_GRID_CELL_ID = "E148000_N170000"
HISTORICAL_BBOX = [148000.0, 170000.0, 148500.0, 170500.0]
EXPECTED_GRAND_PLACE_CELL_ID = "bxl-e148500-n170500-s500"
EXPECTED_GRAND_PLACE_GRID_CELL_ID = "E148500_N170500"
EXPECTED_GRAND_PLACE_BBOX = [148500.0, 170500.0, 149000.0, 171000.0]
EXPECTED_MUNICIPALITY_SEMANTIC_SHA256 = "f425d22f2a4530da40c3acbd951387b2e61eb311497c8ef3b5cbbce54897ffdb"
EXPECTED_MUNICIPALITY_ID = "https://databrussels.be/id/municipality/5000074"
EXPECTED_NIS = "21004"
EXPECTED_SOURCE_MANIFEST_SHA256 = "4c18e124adfbdb230fcd357c444f58c1d532db2812f77d6f97380676f60e00c7"
EXPECTED_SOURCE_DIGEST = "bbee45393ca07d86515f160e6eb9511c624440ccced97dff564b133eeafe7feb"
EXPECTED_SOURCE_LAYER_COUNTS = {
    "buildings": 772,
    "street_axes": 97,
    "street_surfaces": 410,
    "train_network": 28,
    "tram_network": 28,
}
SUPERSEDED_READY_SEMANTIC_SHA256 = "b84398dd084e85dce7e065ebd3fc87f873dcf965edb48ba55ea1eae519e61565"
RAILS = [
    "registration_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
]
INDEX_RAILS = [
    "runtime_directory_scan_authorized",
    "road_crosswalk_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
]


def load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise RuntimeError(f"required file missing: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_sha(payload: dict[str, Any]) -> str:
    data = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_false(payload: dict[str, Any], keys: list[str], label: str) -> None:
    for key in keys:
        if payload.get(key) is not False:
            raise RuntimeError(f"{label} must keep {key}=false")


def review(repo_root: Path, municipality_lock_path: Path) -> dict[str, Any]:
    game = repo_root / "grand-bruxelles-game"
    hold = load_json(game / "data/provenance/grand_place_spatial_identity.review.json")
    if hold.get("status") != "SPATIAL_IDENTITY_MISMATCH_HOLD":
        raise RuntimeError("Grand-Place spatial identity HOLD missing")
    if (hold.get("observed_claim") or {}).get("cell_id") != HISTORICAL_CELL_ID:
        raise RuntimeError("historical cell identity drift")
    if (hold.get("expected_target") or {}).get("cell_id") != EXPECTED_GRAND_PLACE_CELL_ID:
        raise RuntimeError("expected Grand-Place cell identity drift")
    require_false(hold.get("authorization") or {}, list((hold.get("authorization") or {}).keys()), "spatial HOLD")

    lock = load_json(municipality_lock_path)
    stable = lock.get("stable_measurement") or {}
    cell = stable.get("cell") or {}
    if cell.get("grid_cell_id") != HISTORICAL_GRID_CELL_ID or [float(v) for v in cell.get("bbox", [])] != HISTORICAL_BBOX:
        raise RuntimeError("historical municipality lock cell drift")
    if stable.get("semantic_sha256") != EXPECTED_MUNICIPALITY_SEMANTIC_SHA256:
        raise RuntimeError("historical municipality semantic lock drift")
    coverage = stable.get("municipality_coverage") or {}
    if coverage.get("municipality_id") != EXPECTED_MUNICIPALITY_ID or str(coverage.get("municipality_niscode")) != EXPECTED_NIS:
        raise RuntimeError("historical municipality identity drift")

    source_path = game / f"data/urbis/remaining_brussels/cells/{HISTORICAL_CELL_ID}/manifest.json"
    if file_sha256(source_path) != EXPECTED_SOURCE_MANIFEST_SHA256:
        raise RuntimeError("historical authoritative source manifest byte hash drift")
    source = load_json(source_path)
    if source.get("cell_id") != HISTORICAL_CELL_ID or [float(v) for v in source.get("bbox", [])] != HISTORICAL_BBOX:
        raise RuntimeError("historical authoritative source target drift")
    if source.get("source_digest") != EXPECTED_SOURCE_DIGEST:
        raise RuntimeError("historical source digest drift")
    counts = {name: int((source.get("layers") or {}).get(name, {}).get("features", -1)) for name in EXPECTED_SOURCE_LAYER_COUNTS}
    if counts != EXPECTED_SOURCE_LAYER_COUNTS:
        raise RuntimeError("historical source layer accounting drift")

    historical_canonical = game / f"data/cell_manifests/{HISTORICAL_CELL_ID}.json"
    expected_canonical = game / f"data/cell_manifests/{EXPECTED_GRAND_PLACE_CELL_ID}.json"
    expected_source = game / f"data/urbis/remaining_brussels/cells/{EXPECTED_GRAND_PLACE_CELL_ID}/manifest.json"
    if not historical_canonical.is_file():
        raise RuntimeError("historical generic canonical evidence cell missing")
    if expected_canonical.exists() or expected_source.exists():
        raise RuntimeError("correct Grand-Place target must use separate acquisition/registration gates")

    index = load_json(game / "data/provenance/brussels_registered_cell_manifest_index.json")
    rows = {str(row.get("cell_id")): row for row in index.get("entries", [])}
    if HISTORICAL_CELL_ID not in rows or EXPECTED_GRAND_PLACE_CELL_ID in rows:
        raise RuntimeError("registered-cell spatial identity contract drift")
    require_false(index, INDEX_RAILS, "registered-cell index")

    result: dict[str, Any] = {
        "schema": "grand-bruxelles-grand-place-cell-registration-review-v1",
        "status": "SPATIAL_IDENTITY_MISMATCH_HOLD",
        "spatial_identity_review": "data/provenance/grand_place_spatial_identity.review.json",
        "target": {
            "cell_id": HISTORICAL_CELL_ID,
            "grid_cell_id": HISTORICAL_GRID_CELL_ID,
            "crs": "EPSG:31370",
            "bbox": HISTORICAL_BBOX,
            "canonical_manifest_path": f"data/cell_manifests/{HISTORICAL_CELL_ID}.json",
            "authoritative_source_manifest_path": f"data/urbis/remaining_brussels/cells/{HISTORICAL_CELL_ID}/manifest.json",
            "canonical_manifest_present": True,
            "authoritative_source_manifest_present": True,
            "treat_as_grand_place": False,
        },
        "expected_grand_place_target": {
            "cell_id": EXPECTED_GRAND_PLACE_CELL_ID,
            "grid_cell_id": EXPECTED_GRAND_PLACE_GRID_CELL_ID,
            "crs": "EPSG:31370",
            "bbox": EXPECTED_GRAND_PLACE_BBOX,
            "authoritative_source_manifest_present": False,
            "canonical_manifest_present": False,
        },
        "municipality_evidence": {
            "lock_path": "data/provenance/grand_place_road_cell_municipality.measurement.json",
            "semantic_sha256": EXPECTED_MUNICIPALITY_SEMANTIC_SHA256,
            "municipality_id": EXPECTED_MUNICIPALITY_ID,
            "municipality_niscode": EXPECTED_NIS,
            "coverage_ratio": 1.0,
            "road_ids": [13842686, 684214770],
            "point_hits": 9,
            "segment_hits": 7,
            "spatial_identity_use": "historical_only_not_grand_place",
        },
        "registered_cell_index": {
            "path": "data/provenance/brussels_registered_cell_manifest_index.json",
            "registered_cell_count": int(index.get("registered_cell_count", -1)),
            "historical_cell_registered": True,
            "grand_place_target_registered": False,
        },
        "authoritative_source_evidence": {
            "manifest_sha256": EXPECTED_SOURCE_MANIFEST_SHA256,
            "source_digest": EXPECTED_SOURCE_DIGEST,
            "format": "grand-bruxelles-urbis-source-cell-v1",
            "promotion": "source_only_no_runtime_mutation",
            "layer_feature_counts": EXPECTED_SOURCE_LAYER_COUNTS,
            "buildings_ownership_filtered": 61,
            "buildings_invalid_ownership_features": 0,
            "spatial_identity": "historical_generic_cell_not_grand_place",
        },
        "supersedes_semantic_sha256": SUPERSEDED_READY_SEMANTIC_SHA256,
        "blocker": "The historical source cell is valid generic evidence but is spatially outside the official Grand-Place anchor. Acquire authoritative source for bxl-e148500-n170500-s500 before any Grand-Place canonical review.",
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
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--municipality-lock", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = review(Path(args.repo_root), Path(args.municipality_lock))
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "GRAND_PLACE_CELL_REGISTRATION_SPATIAL_IDENTITY_HOLD: "
        f"historical={HISTORICAL_CELL_ID} expected={EXPECTED_GRAND_PLACE_CELL_ID} "
        f"semantic_sha256={result['semantic_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
