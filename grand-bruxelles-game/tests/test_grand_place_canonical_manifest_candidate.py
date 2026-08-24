#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "tools/qa/build_grand_place_canonical_manifest_candidate.py"
spec = importlib.util.spec_from_file_location("candidate", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

BASE = "1dd3aacc9b7c8bfdc697a404f45dc27ba21a58ce"
SOURCE_MANIFEST_TEXT = '''{
  "bbox": [
    148000.0,
    170000.0,
    148500.0,
    170500.0
  ],
  "cell_id": "bxl-e148000-n170000-s500",
  "crs": "EPSG:31370",
  "format": "grand-bruxelles-urbis-source-cell-v1",
  "layers": {
    "buildings": {
      "features": 772,
      "file": "raw/buildings.geojson",
      "invalid_ownership_features": 0,
      "ownership": "canonical_centroid_global_500m_cell",
      "ownership_filtered": 61,
      "wfs_name": "urbisvector:Buildings"
    },
    "street_axes": {
      "features": 97,
      "file": "raw/street_axes.geojson",
      "ownership": "bbox_intersection_source_unclipped",
      "wfs_name": "urbisvector:StreetAxes"
    },
    "street_surfaces": {
      "features": 410,
      "file": "raw/street_surfaces.geojson",
      "ownership": "bbox_intersection_source_unclipped",
      "wfs_name": "urbisvector:StreetSurfaces"
    },
    "train_network": {
      "features": 28,
      "file": "raw/train_network.geojson",
      "ownership": "bbox_intersection_source_unclipped",
      "wfs_name": "urbisvector:TrainNetwork"
    },
    "tram_network": {
      "features": 28,
      "file": "raw/tram_network.geojson",
      "ownership": "bbox_intersection_source_unclipped",
      "wfs_name": "urbisvector:TramNetwork"
    }
  },
  "promotion": "source_only_no_runtime_mutation",
  "source_digest": "bbee45393ca07d86515f160e6eb9511c624440ccced97dff564b133eeafe7feb"
}
'''


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def review() -> dict:
    return {
        "schema": "grand-bruxelles-grand-place-cell-registration-review-v1",
        "status": "READY_FOR_CANONICAL_MANIFEST_REVIEW",
        "target": {
            "cell_id": mod.CELL_ID,
            "crs": mod.CRS,
            "bbox": mod.BBOX,
            "canonical_manifest_present": False,
            "authoritative_source_manifest_present": True,
        },
        "municipality_evidence": {
            "semantic_sha256": mod.MUNICIPALITY_SEMANTIC_SHA,
            "municipality_id": mod.MUNICIPALITY_ID,
            "municipality_niscode": mod.MUNICIPALITY_NIS,
            "coverage_ratio": 1.0,
            "road_ids": [13842686, 684214770],
            "point_hits": 9,
            "segment_hits": 7,
        },
        "authoritative_source_evidence": {
            "manifest_sha256": mod.SOURCE_MANIFEST_SHA,
            "source_digest": mod.SOURCE_DIGEST,
            "format": "grand-bruxelles-urbis-source-cell-v1",
            "promotion": "source_only_no_runtime_mutation",
            "layer_feature_counts": mod.EXPECTED_COUNTS,
            "buildings_ownership_filtered": 61,
            "buildings_invalid_ownership_features": 0,
        },
        "semantic_sha256": mod.REGISTRATION_REVIEW_SHA,
        **{key: False for key in mod.REVIEW_RAILS},
    }


def source_lock() -> dict:
    return {
        "schema": "grand-bruxelles-urbis-source-cell-lock-v2",
        "status": "LOCKED_EXACT_SOURCE_ONLY_PERSISTED",
        "source": {"authority": "Paradigm / Brussels-Capital Region", "license": "CC0-1.0"},
        "locked": {"manifest_source_digest": mod.SOURCE_DIGEST, "source_semantic_sha256": mod.SOURCE_SEMANTIC_SHA},
        "authorization": {
            "source_acquisition": True,
            "source_registration": False,
            "canonical_registration": False,
            "road_to_cell_mapping": False,
            "runtime_mount": False,
            "rendered_geometry": False,
            "collision": False,
            "safe_spawn": False,
            "jouable_promotion": False,
        },
    }


def registered_index() -> dict:
    return {
        "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
        "semantic_sha256": mod.REGISTERED_INDEX_SEMANTIC_SHA,
        "destination_readiness": "REGISTERED_CELL_INDEX_EVIDENCE_ONLY",
        "registered_cell_count": 1,
        "entries": [{"cell_id": "bxl-e149000-n169000-s500"}],
        **{key: False for key in mod.INDEX_RAILS},
    }


def fixture(root: Path) -> None:
    write_json(root / mod.REVIEW_PATH, review())
    write_json(root / mod.SOURCE_LOCK_PATH, source_lock())
    source_path = root / mod.SOURCE_MANIFEST_PATH
    source_path.parent.mkdir(parents=True, exist_ok=True)
    source_path.write_text(SOURCE_MANIFEST_TEXT, encoding="utf-8")
    assert mod._sha256_bytes(source_path.read_bytes()) == mod.SOURCE_MANIFEST_SHA
    write_json(root / mod.REGISTERED_INDEX_PATH, registered_index())


def expect_error(fn, text: str) -> None:
    try:
        fn()
    except RuntimeError as exc:
        assert text in str(exc), (text, exc)
    else:
        raise AssertionError(f"expected RuntimeError containing {text!r}")


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        result, candidate, candidate_bytes = mod.build(root, BASE)
        assert result["status"] == "CANDIDATE_LOCKED_UNREGISTERED"
        assert result["production_base_sha"] == BASE
        assert result["candidate_manifest"]["sha256"] == mod.CANDIDATE_SHA
        assert candidate["maturity"]["state"] == "data_ready"
        assert all(value is False for value in candidate["maturity"]["gates"].values())
        assert result["authorization"]["canonical_manifest_write"] is False
        assert result["registered_cell_index"]["target_registered"] is False
        assert mod._sha256_bytes(candidate_bytes) == mod.CANDIDATE_SHA

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        canonical = root / mod.CANONICAL_PATH
        canonical.parent.mkdir(parents=True, exist_ok=True)
        canonical.write_text("{}\n", encoding="utf-8")
        expect_error(lambda: mod.build(root, BASE), "canonical manifest already exists")

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        payload = review()
        payload["registration_authorized"] = True
        write_json(root / mod.REVIEW_PATH, payload)
        expect_error(lambda: mod.build(root, BASE), "registration review rail opened")

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        payload = review()
        payload["municipality_evidence"]["coverage_ratio"] = 0.99
        write_json(root / mod.REVIEW_PATH, payload)
        expect_error(lambda: mod.build(root, BASE), "municipality coverage no longer complete")

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        payload = registered_index()
        payload["semantic_sha256"] = "0" * 64
        write_json(root / mod.REGISTERED_INDEX_PATH, payload)
        expect_error(lambda: mod.build(root, BASE), "registered-cell index semantic identity drift")

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        payload = source_lock()
        payload["source"]["license"] = "UNKNOWN"
        write_json(root / mod.SOURCE_LOCK_PATH, payload)
        expect_error(lambda: mod.build(root, BASE), "source authority/license drift")

    print("GRAND_PLACE_CANONICAL_MANIFEST_CANDIDATE_REGRESSIONS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
