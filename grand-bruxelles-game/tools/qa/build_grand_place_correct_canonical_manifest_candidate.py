#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

CELL_ID = "bxl-e148500-n170500-s500"
BBOX = [148500.0, 170500.0, 149000.0, 171000.0]
CRS = "EPSG:31370"
SOURCE_MANIFEST_SHA = "f464b35581b9231582daafbd28c07f1b15e3aeae2d7b683385b7073b6b73658f"
SOURCE_DIGEST = "0645d03062f79ec08d2ba87714754633fc48f1a5eadf3a35e0df2ae4244d4302"
SOURCE_SEMANTIC_SHA = "683391007df04a6a6c6c597f3d64411e05b206cf8dd41f7aebaf7d8df76a56e3"
MUNICIPALITY_SEMANTIC_SHA = "31b049a8687f65f7b24458357a7b10b010b22190a627697fad5d1090d04dc979"
MUNICIPALITY_ID = "https://databrussels.be/id/municipality/5000074"
MUNICIPALITY_NIS = "21004"
REGISTERED_INDEX_SEMANTIC_SHA = "488a88cd5c2cb8dae86dd6c79ed276f31a33a2ae12654cccd5653469211fdcd7"
EXPECTED_COUNTS = {
    "buildings": 1110,
    "street_axes": 180,
    "street_surfaces": 598,
    "train_network": 12,
    "tram_network": 12,
}

PREFLIGHT_PATH = Path("data/provenance/grand_place_correct_canonical_registration.review.json")
SOURCE_LOCK_PATH = Path("data/provenance/grand_place_correct_urbis_source_cell.measurement.json")
SOURCE_MANIFEST_PATH = Path("data/urbis/remaining_brussels/cells") / CELL_ID / "manifest.json"
REGISTERED_INDEX_PATH = Path("data/provenance/brussels_registered_cell_manifest_index.json")
CANONICAL_PATH = Path("data/cell_manifests") / f"{CELL_ID}.json"


def read_json(path: Path) -> dict:
    if not path.is_file():
        raise RuntimeError(f"required file missing: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def canonical_sha(payload: dict) -> str:
    return sha256_bytes(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def require_false(payload: dict, keys: tuple[str, ...], label: str) -> None:
    for key in keys:
        if payload.get(key) is not False:
            raise RuntimeError(f"{label} rail opened: {key}")


def validate_preflight(preflight: dict) -> dict:
    if preflight.get("schema") != "grand-bruxelles-grand-place-correct-canonical-registration-review-v1":
        raise RuntimeError("canonical preflight schema drift")
    if preflight.get("status") != "READY_FOR_CANONICAL_MANIFEST_REVIEW":
        raise RuntimeError("canonical preflight is not review-ready")
    target = preflight.get("target") or {}
    if target.get("cell_id") != CELL_ID or target.get("crs") != CRS or target.get("bbox") != BBOX:
        raise RuntimeError("canonical preflight target drift")
    source = preflight.get("source_evidence") or {}
    if source.get("authority") != "Paradigm / Brussels-Capital Region" or source.get("license") != "CC0-1.0":
        raise RuntimeError("canonical preflight authority/license drift")
    if source.get("source_semantic_sha256") != SOURCE_SEMANTIC_SHA or source.get("manifest_sha256") != SOURCE_MANIFEST_SHA:
        raise RuntimeError("canonical preflight source identity drift")
    if source.get("layer_counts") != EXPECTED_COUNTS:
        raise RuntimeError("canonical preflight source accounting drift")
    if int(source.get("buildings_ownership_filtered", -1)) != 70 or int(source.get("buildings_invalid_ownership", -1)) != 0:
        raise RuntimeError("canonical preflight ownership accounting drift")
    municipality = preflight.get("municipality_evidence") or {}
    if municipality.get("status") != "MUNICIPALITY_PROVEN_SINGLE":
        raise RuntimeError("municipality is not proven single")
    if municipality.get("semantic_sha256") != MUNICIPALITY_SEMANTIC_SHA:
        raise RuntimeError("municipality semantic identity drift")
    if municipality.get("municipality_id") != MUNICIPALITY_ID or str(municipality.get("niscode")) != MUNICIPALITY_NIS:
        raise RuntimeError("municipality identity drift")
    if float(municipality.get("coverage_ratio", -1.0)) != 1.0:
        raise RuntimeError("municipality no longer covers the full cell")
    require_false(
        preflight,
        (
            "registration_authorized",
            "road_cell_mapping_authorized",
            "runtime_directory_scan_authorized",
            "runtime_mount_authorized",
            "rendered_geometry_authorized",
            "collision_authorized",
            "safe_spawn_authorized",
            "jouable_promotion_authorized",
        ),
        "canonical preflight",
    )
    return municipality


def build(repo_root: Path, production_base_sha: str) -> tuple[dict, dict, bytes]:
    if not re.fullmatch(r"[0-9a-f]{40}", production_base_sha):
        raise RuntimeError("production_base_sha must be a full lowercase SHA-1")
    if (repo_root / CANONICAL_PATH).exists():
        raise RuntimeError("corrected Grand-Place canonical manifest already exists; candidate-only phase must stop")

    preflight = read_json(repo_root / PREFLIGHT_PATH)
    municipality = validate_preflight(preflight)

    lock = read_json(repo_root / SOURCE_LOCK_PATH)
    if lock.get("schema") != "grand-bruxelles-urbis-source-cell-semantic-measurement-v1":
        raise RuntimeError("source lock schema drift")
    if lock.get("cell_id") != CELL_ID or lock.get("crs") != CRS or lock.get("bbox") != BBOX:
        raise RuntimeError("source lock target drift")
    if lock.get("source_semantic_sha256") != SOURCE_SEMANTIC_SHA or lock.get("manifest_source_digest") != SOURCE_DIGEST:
        raise RuntimeError("source semantic identity drift")
    counts = {name: int(row["features"]) for name, row in (lock.get("layers") or {}).items()}
    if counts != EXPECTED_COUNTS:
        raise RuntimeError("source lock layer accounting drift")
    buildings = (lock.get("layers") or {}).get("buildings") or {}
    if int(buildings.get("ownership_filtered", -1)) != 70 or int(buildings.get("invalid_ownership_features", -1)) != 0:
        raise RuntimeError("source lock building ownership accounting drift")
    require_false(
        lock,
        (
            "registration_authorized",
            "runtime_mount_authorized",
            "rendered_geometry_authorized",
            "collision_authorized",
            "safe_spawn_authorized",
            "jouable_promotion_authorized",
        ),
        "source lock",
    )

    source_path = repo_root / SOURCE_MANIFEST_PATH
    raw = source_path.read_bytes()
    if sha256_bytes(raw) != SOURCE_MANIFEST_SHA:
        raise RuntimeError("source manifest byte hash drift")
    source = json.loads(raw)
    if source.get("cell_id") != CELL_ID or source.get("crs") != CRS or source.get("bbox") != BBOX:
        raise RuntimeError("source manifest target drift")
    if source.get("promotion") != "source_only_no_runtime_mutation" or source.get("source_digest") != SOURCE_DIGEST:
        raise RuntimeError("source manifest provenance drift")
    source_counts = {name: int(row["features"]) for name, row in (source.get("layers") or {}).items()}
    if source_counts != EXPECTED_COUNTS:
        raise RuntimeError("source manifest layer accounting drift")

    index = read_json(repo_root / REGISTERED_INDEX_PATH)
    if int(index.get("registered_cell_count", -1)) != 3:
        raise RuntimeError("registered-cell baseline count drift")
    if index.get("semantic_sha256") != REGISTERED_INDEX_SEMANTIC_SHA:
        raise RuntimeError("registered-cell index semantic identity drift")
    if any(str(row.get("cell_id")) == CELL_ID for row in index.get("entries", [])):
        raise RuntimeError("corrected Grand-Place cell is already registered")
    require_false(
        index,
        (
            "runtime_directory_scan_authorized",
            "road_crosswalk_authorized",
            "runtime_mount_authorized",
            "rendered_geometry_authorized",
            "collision_authorized",
            "safe_spawn_authorized",
            "jouable_promotion_authorized",
        ),
        "registered index",
    )

    candidate = {
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
            "license": "CC0-1.0",
            "municipality_assignment_policy": "single_official_municipality_proven_full_cell_coverage",
            "municipality": {
                "coverage_ratio": 1.0,
                "inspire_id": MUNICIPALITY_ID,
                "niscode": MUNICIPALITY_NIS,
            },
            "municipality_semantic_sha256": MUNICIPALITY_SEMANTIC_SHA,
            "primary": "UrbIS WFS / Paradigm",
            "source_records_present": True,
            "source_semantic_sha256": SOURCE_SEMANTIC_SHA,
        },
        "transport": {
            "rail_geometry_present": True,
            "service_simulation_validated": False,
            "tram_geometry_present": True,
        },
        "uncertainties": [
            "terrain and height evidence are not registered for this canonical cell",
            "runtime geometry, streaming, collisions, photo-match and performance remain unvalidated",
        ],
    }
    candidate_bytes = (json.dumps(candidate, indent=2, sort_keys=True) + "\n").encode("utf-8")
    candidate_sha = sha256_bytes(candidate_bytes)
    result = {
        "schema": "grand-bruxelles-grand-place-correct-canonical-manifest-candidate-review-v1",
        "status": "CANDIDATE_MEASURED_UNREGISTERED",
        "production_base_sha": production_base_sha,
        "target": {
            "cell_id": CELL_ID,
            "crs": CRS,
            "bbox": BBOX,
            "canonical_manifest_path": CANONICAL_PATH.as_posix(),
            "canonical_manifest_present": False,
        },
        "source_evidence": {
            "lock_path": SOURCE_LOCK_PATH.as_posix(),
            "authority": "Paradigm / Brussels-Capital Region",
            "license": "CC0-1.0",
            "source_manifest_path": SOURCE_MANIFEST_PATH.as_posix(),
            "source_manifest_sha256": SOURCE_MANIFEST_SHA,
            "source_digest": SOURCE_DIGEST,
            "source_semantic_sha256": SOURCE_SEMANTIC_SHA,
        },
        "municipality_evidence": {
            "semantic_sha256": MUNICIPALITY_SEMANTIC_SHA,
            "assignment_policy": "single_official_municipality_proven_full_cell_coverage",
            "municipality_id": municipality["municipality_id"],
            "niscode": str(municipality["niscode"]),
            "coverage_ratio": float(municipality["coverage_ratio"]),
        },
        "candidate_manifest": {
            "artifact_filename": f"{CELL_ID}.candidate.json",
            "sha256": candidate_sha,
            "format": candidate["format"],
            "maturity_state": "data_ready",
            "all_maturity_gates_false": True,
        },
        "registered_cell_index": {
            "path": REGISTERED_INDEX_PATH.as_posix(),
            "registered_cell_count": 3,
            "semantic_sha256": REGISTERED_INDEX_SEMANTIC_SHA,
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
        "next_action": "lock this measured candidate in a separate review file; do not write the canonical manifest or mutate the registered-cell index in this lot",
    }
    semantic = {key: value for key, value in result.items() if key != "production_base_sha"}
    result["semantic_sha256"] = canonical_sha(semantic)
    return result, candidate, candidate_bytes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", required=True)
    ap.add_argument("--production-base-sha", required=True)
    ap.add_argument("--out-candidate", required=True)
    ap.add_argument("--out-review", required=True)
    args = ap.parse_args()
    review, _, candidate_bytes = build(Path(args.repo_root), args.production_base_sha)
    out_candidate = Path(args.out_candidate)
    out_review = Path(args.out_review)
    out_candidate.parent.mkdir(parents=True, exist_ok=True)
    out_review.parent.mkdir(parents=True, exist_ok=True)
    out_candidate.write_bytes(candidate_bytes)
    out_review.write_text(json.dumps(review, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "GRAND_PLACE_CORRECT_CANONICAL_MANIFEST_CANDIDATE_MEASURED_UNREGISTERED: "
        f"candidate_sha={review['candidate_manifest']['sha256']} semantic_sha={review['semantic_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
