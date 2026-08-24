#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "tools/qa/review_grand_place_cell_registration.py"
spec = importlib.util.spec_from_file_location("registration_review", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def municipality_lock() -> dict:
    rails = {key: False for key in mod.RAILS}
    return {
        "schema": "grand-bruxelles-road-cell-municipality-preflight-lock-v3",
        "status": "LOCKED_SOURCE_ONLY_V2_REBOUND",
        "stable_measurement": {
            "schema": "grand-bruxelles-road-cell-municipality-preflight-v3",
            "status": "MUNICIPALITY_PROVEN_SINGLE",
            "candidate_source": {},
            "cell": {
                "grid_cell_id": mod.TARGET_GRID_CELL_ID,
                "bbox": mod.TARGET_BBOX,
                "road_count": 2,
                "road_ids": [13842686, 684214770],
                "point_hits": 9,
                "segment_hits": 7,
            },
            "municipality_coverage": {
                "status": "MUNICIPALITY_PROVEN_SINGLE",
                "municipality_id": mod.EXPECTED_MUNICIPALITY_ID,
                "municipality_niscode": mod.EXPECTED_NIS,
                "coverage_ratio": 1.0,
                **rails,
            },
            "semantic_sha256": mod.EXPECTED_MUNICIPALITY_SEMANTIC_SHA256,
            **rails,
        },
        **rails,
    }


def registered_index() -> dict:
    return {
        "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
        "semantic_sha256": mod.EXPECTED_REGISTERED_INDEX_SEMANTIC_SHA256,
        "registered_cell_count": 1,
        "entries": [{"cell_id": "bxl-e149000-n169000-s500"}],
        "runtime_directory_scan_authorized": False,
        "road_crosswalk_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }


def source_manifest() -> dict:
    return {
        "bbox": mod.TARGET_BBOX,
        "cell_id": mod.TARGET_CELL_ID,
        "crs": "EPSG:31370",
        "format": "grand-bruxelles-urbis-source-cell-v1",
        "layers": {
            "buildings": {
                "features": 772,
                "file": "raw/buildings.geojson",
                "invalid_ownership_features": 0,
                "ownership": "canonical_centroid_global_500m_cell",
                "ownership_filtered": 61,
                "wfs_name": "urbisvector:Buildings",
            },
            "street_axes": {
                "features": 97,
                "file": "raw/street_axes.geojson",
                "ownership": "bbox_intersection_source_unclipped",
                "wfs_name": "urbisvector:StreetAxes",
            },
            "street_surfaces": {
                "features": 410,
                "file": "raw/street_surfaces.geojson",
                "ownership": "bbox_intersection_source_unclipped",
                "wfs_name": "urbisvector:StreetSurfaces",
            },
            "train_network": {
                "features": 28,
                "file": "raw/train_network.geojson",
                "ownership": "bbox_intersection_source_unclipped",
                "wfs_name": "urbisvector:TrainNetwork",
            },
            "tram_network": {
                "features": 28,
                "file": "raw/tram_network.geojson",
                "ownership": "bbox_intersection_source_unclipped",
                "wfs_name": "urbisvector:TramNetwork",
            },
        },
        "promotion": "source_only_no_runtime_mutation",
        "source_digest": mod.EXPECTED_SOURCE_DIGEST,
    }


def write_fixture(root: Path, *, registered_target: bool = False, source_mutator=None) -> Path:
    prov = root / "grand-bruxelles-game/data/provenance"
    prov.mkdir(parents=True)
    lock_path = prov / "grand_place_road_cell_municipality.measurement.json"
    lock_path.write_text(json.dumps(municipality_lock()), encoding="utf-8")
    index = registered_index()
    if registered_target:
        index["entries"].append({"cell_id": mod.TARGET_CELL_ID})
        index["registered_cell_count"] = 2
    (prov / "brussels_registered_cell_manifest_index.json").write_text(json.dumps(index), encoding="utf-8")

    source = root / f"grand-bruxelles-game/data/urbis/remaining_brussels/cells/{mod.TARGET_CELL_ID}/manifest.json"
    source.parent.mkdir(parents=True)
    payload = source_manifest()
    if source_mutator:
        source_mutator(payload)
    source.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return lock_path


def expect_runtime_error(fn, text: str) -> None:
    try:
        fn()
    except RuntimeError as exc:
        assert text in str(exc), (text, exc)
    else:
        raise AssertionError(f"expected RuntimeError containing {text!r}")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        lock = write_fixture(root)
        result = mod.review(root, lock)
        assert result["status"] == "READY_FOR_CANONICAL_MANIFEST_REVIEW"
        assert result["target"]["authoritative_source_manifest_present"] is True
        assert result["authoritative_source_evidence"]["source_digest"] == mod.EXPECTED_SOURCE_DIGEST
        for key in mod.RAILS:
            assert result[key] is False

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        lock = write_fixture(root, registered_target=True)
        expect_runtime_error(lambda: mod.review(root, lock), "already registered")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        lock = write_fixture(root)
        payload = json.loads(lock.read_text())
        payload["stable_measurement"]["municipality_coverage"]["coverage_ratio"] = 0.99
        lock.write_text(json.dumps(payload), encoding="utf-8")
        expect_runtime_error(lambda: mod.review(root, lock), "coverage no longer complete")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        lock = write_fixture(root, source_mutator=lambda p: p.__setitem__("crs", "EPSG:4326"))
        expect_runtime_error(lambda: mod.review(root, lock), "byte hash drift")

    print("GRAND_PLACE_CELL_REGISTRATION_REVIEW_TESTS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
