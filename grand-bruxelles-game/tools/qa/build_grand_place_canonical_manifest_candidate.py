#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

CELL_ID = "bxl-e148000-n170000-s500"
BBOX = [148000.0, 170000.0, 148500.0, 170500.0]
CRS = "EPSG:31370"
MUNICIPALITY_ID = "https://databrussels.be/id/municipality/5000074"
MUNICIPALITY_NIS = "21004"
MUNICIPALITY_SEMANTIC_SHA = "f425d22f2a4530da40c3acbd951387b2e61eb311497c8ef3b5cbbce54897ffdb"
REGISTRATION_REVIEW_SHA = "b84398dd084e85dce7e065ebd3fc87f873dcf965edb48ba55ea1eae519e61565"
REGISTERED_INDEX_SEMANTIC_SHA = "606c57c18fac82bcd74b4bb870e37d89ff31c775b3fa57533559c17d7a75de6f"
SOURCE_MANIFEST_SHA = "4c18e124adfbdb230fcd357c444f58c1d532db2812f77d6f97380676f60e00c7"
SOURCE_DIGEST = "bbee45393ca07d86515f160e6eb9511c624440ccced97dff564b133eeafe7feb"
SOURCE_SEMANTIC_SHA = "99cb25db4c95860c02dff5cf25c19cc5a4e11a75166f1fe92734edd1b5a0e7d4"
CANDIDATE_SHA = "b454022050e850214eeb8d5345fe574e831dcaba6a832123a7dfe44070d0b020"
REVIEW_SEMANTIC_SHA = "bb0a23818b738b22b20aea1d9c37ecf794827e05d5d4ab8fed4f758d0c6f197e"
EXPECTED_COUNTS = {
    "buildings": 772,
    "street_axes": 97,
    "street_surfaces": 410,
    "train_network": 28,
    "tram_network": 28,
}

REVIEW_PATH = Path("data/provenance/grand_place_cell_registration.review.json")
SOURCE_LOCK_PATH = Path("data/provenance/grand_place_urbis_source_cell.measurement.json")
SOURCE_MANIFEST_PATH = Path("data/urbis/remaining_brussels/cells") / CELL_ID / "manifest.json"
REGISTERED_INDEX_PATH = Path("data/provenance/brussels_registered_cell_manifest_index.json")
CANONICAL_PATH = Path("data/cell_manifests") / f"{CELL_ID}.json"

REVIEW_RAILS = (
    "registration_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)
INDEX_RAILS = (
    "runtime_directory_scan_authorized",
    "road_crosswalk_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)


def _read_json(path: Path) -> dict:
    if not path.is_file():
        raise RuntimeError(f"required file missing: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _canonical_sha(payload: dict) -> str:
    return _sha256_bytes(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def _candidate_manifest(source: dict, source_lock: dict) -> dict:
    counts = {name: int(row["features"]) for name, row in source["layers"].items()}
    if counts != EXPECTED_COUNTS:
        raise RuntimeError(f"source layer accounting drift: {counts!r}")
    return {
        "bbox": BBOX,
        "cell_id": CELL_ID,
        "collisions": {"status": "not_validated"},
        "crs": CRS,
        "format": "grand-bruxelles-cell-maturity-v1",
        "geometry": {
            "authoritative_geometry_ready": True,
            "layer_feature_counts": EXPECTED_COUNTS,
            "layers": ["buildings", "street_surfaces", "street_axes", "tram_network", "train_network"],
            "source_digest": SOURCE_DIGEST,
            "source_manifest": SOURCE_MANIFEST_PATH.as_posix(),
        },
        "maturity": {
            "gates": {
                "collisions": False,
                "heights": False,
                "performance": False,
                "photo_match": False,
                "runtime_geometry": False,
                "streaming": False,
                "terrain": False,
            },
            "state": "data_ready",
        },
        "provenance": {
            "authoritative_source_manifest": SOURCE_MANIFEST_PATH.as_posix(),
            "authoritative_source_manifest_sha256": SOURCE_MANIFEST_SHA,
            "license": source_lock["source"]["license"],
            "municipality_coverage_ratio": 1.0,
            "municipality_id": MUNICIPALITY_ID,
            "municipality_niscode": MUNICIPALITY_NIS,
            "primary": "UrbIS WFS / Paradigm",
            "source_records_present": True,
            "source_semantic_sha256": SOURCE_SEMANTIC_SHA,
        },
        "transport": {
            "rail_geometry_present": EXPECTED_COUNTS["train_network"] > 0,
            "service_simulation_validated": False,
            "tram_geometry_present": EXPECTED_COUNTS["tram_network"] > 0,
        },
        "uncertainties": [
            "terrain evidence is not registered for this canonical cell",
            "height evidence is not registered for this canonical cell",
            "runtime geometry, streaming, collisions, photo-match and performance remain unvalidated",
        ],
    }


def build(repo_root: Path, production_base_sha: str) -> tuple[dict, dict, bytes]:
    if not re.fullmatch(r"[0-9a-f]{40}", production_base_sha):
        raise RuntimeError("production_base_sha must be a full lowercase SHA-1")
    canonical_path = repo_root / CANONICAL_PATH
    if canonical_path.exists():
        raise RuntimeError("canonical manifest already exists; candidate-only review must stop")

    review = _read_json(repo_root / REVIEW_PATH)
    if review.get("schema") != "grand-bruxelles-grand-place-cell-registration-review-v1":
        raise RuntimeError("registration review schema drift")
    if review.get("status") != "READY_FOR_CANONICAL_MANIFEST_REVIEW":
        raise RuntimeError("registration review is not READY")
    if review.get("semantic_sha256") != REGISTRATION_REVIEW_SHA:
        raise RuntimeError("registration review semantic identity drift")
    target = review.get("target") or {}
    if target.get("cell_id") != CELL_ID or target.get("crs") != CRS or target.get("bbox") != BBOX:
        raise RuntimeError("registration review target drift")
    if target.get("canonical_manifest_present") is not False or target.get("authoritative_source_manifest_present") is not True:
        raise RuntimeError("registration review presence contract drift")
    municipality = review.get("municipality_evidence") or {}
    if municipality.get("semantic_sha256") != MUNICIPALITY_SEMANTIC_SHA:
        raise RuntimeError("municipality semantic identity drift")
    if municipality.get("municipality_id") != MUNICIPALITY_ID or municipality.get("municipality_niscode") != MUNICIPALITY_NIS:
        raise RuntimeError("municipality identity drift")
    if float(municipality.get("coverage_ratio", -1.0)) != 1.0:
        raise RuntimeError("municipality coverage no longer complete")
    if municipality.get("road_ids") != [13842686, 684214770] or municipality.get("point_hits") != 9 or municipality.get("segment_hits") != 7:
        raise RuntimeError("municipality road evidence drift")
    review_source = review.get("authoritative_source_evidence") or {}
    if review_source.get("manifest_sha256") != SOURCE_MANIFEST_SHA or review_source.get("source_digest") != SOURCE_DIGEST:
        raise RuntimeError("registration review source identity drift")
    if review_source.get("format") != "grand-bruxelles-urbis-source-cell-v1" or review_source.get("promotion") != "source_only_no_runtime_mutation":
        raise RuntimeError("registration review source contract drift")
    if review_source.get("layer_feature_counts") != EXPECTED_COUNTS:
        raise RuntimeError("registration review layer accounting drift")
    if review_source.get("buildings_ownership_filtered") != 61 or review_source.get("buildings_invalid_ownership_features") != 0:
        raise RuntimeError("registration review building ownership accounting drift")
    for key in REVIEW_RAILS:
        if review.get(key) is not False:
            raise RuntimeError(f"registration review rail opened: {key}")

    source_lock = _read_json(repo_root / SOURCE_LOCK_PATH)
    if source_lock.get("schema") != "grand-bruxelles-urbis-source-cell-lock-v2":
        raise RuntimeError("source lock schema drift")
    if source_lock.get("status") != "LOCKED_EXACT_SOURCE_ONLY_PERSISTED":
        raise RuntimeError("source lock is not persisted locked-exact")
    source = source_lock.get("source") or {}
    if source.get("authority") != "Paradigm / Brussels-Capital Region" or source.get("license") != "CC0-1.0":
        raise RuntimeError("source authority/license drift")
    locked = source_lock.get("locked") or {}
    if locked.get("manifest_source_digest") != SOURCE_DIGEST or locked.get("source_semantic_sha256") != SOURCE_SEMANTIC_SHA:
        raise RuntimeError("source semantic lock drift")
    auth = source_lock.get("authorization") or {}
    if auth.get("source_acquisition") is not True:
        raise RuntimeError("source acquisition proof missing")
    for key in ("source_registration", "canonical_registration", "road_to_cell_mapping", "runtime_mount", "rendered_geometry", "collision", "safe_spawn", "jouable_promotion"):
        if auth.get(key) is not False:
            raise RuntimeError(f"source lock authorization opened: {key}")

    source_manifest_path = repo_root / SOURCE_MANIFEST_PATH
    raw_source_manifest = source_manifest_path.read_bytes()
    if _sha256_bytes(raw_source_manifest) != SOURCE_MANIFEST_SHA:
        raise RuntimeError("authoritative source manifest byte hash drift")
    source_manifest = json.loads(raw_source_manifest)
    if source_manifest.get("cell_id") != CELL_ID or source_manifest.get("crs") != CRS or source_manifest.get("bbox") != BBOX:
        raise RuntimeError("authoritative source manifest target drift")
    if source_manifest.get("promotion") != "source_only_no_runtime_mutation" or source_manifest.get("source_digest") != SOURCE_DIGEST:
        raise RuntimeError("authoritative source manifest provenance drift")
    counts = {name: int(row["features"]) for name, row in (source_manifest.get("layers") or {}).items()}
    if counts != EXPECTED_COUNTS:
        raise RuntimeError("authoritative source layer accounting drift")
    buildings = source_manifest["layers"]["buildings"]
    if buildings.get("ownership_filtered") != 61 or buildings.get("invalid_ownership_features") != 0:
        raise RuntimeError("authoritative source building ownership accounting drift")

    index = _read_json(repo_root / REGISTERED_INDEX_PATH)
    if index.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise RuntimeError("registered-cell index schema drift")
    if index.get("semantic_sha256") != REGISTERED_INDEX_SEMANTIC_SHA:
        raise RuntimeError("registered-cell index semantic identity drift")
    if index.get("destination_readiness") != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise RuntimeError("registered-cell index readiness drift")
    if int(index.get("registered_cell_count", -1)) != 1:
        raise RuntimeError("registered-cell baseline count drift")
    if any(str(row.get("cell_id")) == CELL_ID for row in index.get("entries", [])):
        raise RuntimeError("target cell is already registered")
    for key in INDEX_RAILS:
        if index.get(key) is not False:
            raise RuntimeError(f"registered-cell index rail opened: {key}")

    candidate = _candidate_manifest(source_manifest, source_lock)
    candidate_bytes = (json.dumps(candidate, indent=2, sort_keys=True) + "\n").encode("utf-8")
    candidate_sha = _sha256_bytes(candidate_bytes)
    if candidate_sha != CANDIDATE_SHA:
        raise RuntimeError(f"candidate manifest identity drift: {candidate_sha}")

    result = {
        "schema": "grand-bruxelles-grand-place-canonical-manifest-candidate-review-v1",
        "status": "CANDIDATE_LOCKED_UNREGISTERED",
        "production_base_sha": production_base_sha,
        "target": {
            "cell_id": CELL_ID,
            "crs": CRS,
            "bbox": BBOX,
            "canonical_manifest_path": CANONICAL_PATH.as_posix(),
            "canonical_manifest_present": False,
        },
        "registration_review": {
            "path": REVIEW_PATH.as_posix(),
            "status": "READY_FOR_CANONICAL_MANIFEST_REVIEW",
            "semantic_sha256": REGISTRATION_REVIEW_SHA,
        },
        "source_evidence": {
            "lock_path": SOURCE_LOCK_PATH.as_posix(),
            "authority": source["authority"],
            "license": source["license"],
            "source_manifest_path": SOURCE_MANIFEST_PATH.as_posix(),
            "source_manifest_sha256": SOURCE_MANIFEST_SHA,
            "source_digest": SOURCE_DIGEST,
            "source_semantic_sha256": SOURCE_SEMANTIC_SHA,
        },
        "municipality_evidence": {
            "municipality_id": MUNICIPALITY_ID,
            "municipality_niscode": MUNICIPALITY_NIS,
            "coverage_ratio": 1.0,
        },
        "candidate_manifest": {
            "artifact_filename": f"{CELL_ID}.candidate.json",
            "sha256": candidate_sha,
            "format": candidate["format"],
            "maturity_state": candidate["maturity"]["state"],
            "all_maturity_gates_false": all(value is False for value in candidate["maturity"]["gates"].values()),
        },
        "registered_cell_index": {
            "path": REGISTERED_INDEX_PATH.as_posix(),
            "registered_cell_count": 1,
            "target_registered": False,
        },
        "authorization": {
            "canonical_manifest_write": False,
            "registered_index_mutation": False,
            "road_to_cell_mapping": False,
            "runtime_mount": False,
            "rendered_geometry": False,
            "collision": False,
            "safe_spawn": False,
            "jouable_promotion": False,
        },
        "blocker": "candidate manifest is locked for separate human/engineering review; canonical path and registered-cell index remain untouched",
    }
    semantic = {key: value for key, value in result.items() if key != "production_base_sha"}
    result["semantic_sha256"] = _canonical_sha(semantic)
    if result["semantic_sha256"] != REVIEW_SEMANTIC_SHA:
        raise RuntimeError("candidate review semantic identity drift")
    return result, candidate, candidate_bytes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--out-candidate", required=True)
    parser.add_argument("--out-review", required=True)
    args = parser.parse_args()
    result, candidate, candidate_bytes = build(Path(args.repo_root), args.production_base_sha)
    candidate_out = Path(args.out_candidate)
    review_out = Path(args.out_review)
    candidate_out.parent.mkdir(parents=True, exist_ok=True)
    review_out.parent.mkdir(parents=True, exist_ok=True)
    candidate_out.write_bytes(candidate_bytes)
    review_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "GRAND_PLACE_CANONICAL_MANIFEST_CANDIDATE_LOCKED_UNREGISTERED: "
        f"candidate_sha256={result['candidate_manifest']['sha256']} semantic_sha256={result['semantic_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
