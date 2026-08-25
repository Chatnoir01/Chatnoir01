#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

CELL_ID = "bxl-e147500-n170000-s500"
BBOX = [147500.0, 170000.0, 148000.0, 170500.0]
CRS = "EPSG:31370"
SOURCE_MANIFEST_SHA = "01113c2cf21fb5732f42c01c47814fbfd2270836af81fad9a7f7f0491130233a"
SOURCE_DIGEST = "fc8851eeb05032e97b3fab39f01349e749edfe1c90713105a4aa1edab3c9521b"
SOURCE_SEMANTIC_SHA = "f88ece4309964ed9939de100424716c90a59409db66924332abb8ea00ff652e0"
BOUNDARY_SEMANTIC_SHA = "c01208a81d61d51492b928f7381991e0fdacd68f62e8ac7a77be8ba08f46ff63"
EXPECTED_COUNTS = {"buildings": 799, "street_axes": 76, "street_surfaces": 310, "train_network": 14, "tram_network": 14}
EXPECTED_INTERSECTIONS = [
    {"niscode": "21001", "inspire_id": "https://databrussels.be/id/municipality/5000071", "coverage_ratio": 0.8320850629128363},
    {"niscode": "21004", "inspire_id": "https://databrussels.be/id/municipality/5000074", "coverage_ratio": 0.16791493708716362},
]

CONTRACT_PATH = Path("data/qa/bourse_canonical_registration_review.contract.json")
SOURCE_LOCK_PATH = Path("data/provenance/bourse_urbis_source_cell.measurement.json")
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


def validate_boundary(boundary: dict) -> list[dict]:
    if boundary.get("semantic_sha256") != BOUNDARY_SEMANTIC_SHA:
        raise RuntimeError("municipality boundary semantic identity drift")
    if boundary.get("automatic_municipality_assignment_authorized") is not False:
        raise RuntimeError("dominant-municipality shortcut became authorized")
    rows = boundary.get("intersections") or []
    normalized = [{"niscode": str(r.get("niscode")), "inspire_id": str(r.get("inspire_id")), "coverage_ratio": float(r.get("coverage_ratio", -1))} for r in rows]
    if normalized != EXPECTED_INTERSECTIONS:
        raise RuntimeError(f"municipality boundary intersections drift: {normalized!r}")
    if abs(sum(r["coverage_ratio"] for r in normalized) - 1.0) > 1e-12:
        raise RuntimeError("municipality boundary coverage no longer sums to 1")
    return normalized


def build(repo_root: Path, production_base_sha: str) -> tuple[dict, dict, bytes]:
    if not re.fullmatch(r"[0-9a-f]{40}", production_base_sha):
        raise RuntimeError("production_base_sha must be a full lowercase SHA-1")
    if (repo_root / CANONICAL_PATH).exists():
        raise RuntimeError("canonical Bourse manifest already exists; candidate-only phase must stop")

    contract = read_json(repo_root / CONTRACT_PATH)
    if contract.get("schema") != "grand-bruxelles-bourse-canonical-registration-review-contract-v1":
        raise RuntimeError("review contract schema drift")
    if contract.get("expected_status") != "READY_FOR_CANONICAL_MANIFEST_REVIEW_BOUNDARY_CELL":
        raise RuntimeError("review contract is not in candidate-review phase")
    for key in ("registration_authorized", "road_cell_mapping_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"):
        if contract.get(key) is not False:
            raise RuntimeError(f"review contract rail opened: {key}")
    intersections = validate_boundary(contract.get("municipality_boundary") or {})

    lock = read_json(repo_root / SOURCE_LOCK_PATH)
    if lock.get("status") != "LOCKED_EXACT_SOURCE_ONLY_PERSISTED":
        raise RuntimeError("source cell is not locked/persisted")
    if lock.get("authority") != "Paradigm / Brussels-Capital Region" or lock.get("license") != "CC0-1.0":
        raise RuntimeError("source authority/license drift")
    if lock.get("source_semantic_sha256") != SOURCE_SEMANTIC_SHA or lock.get("manifest_source_digest") != SOURCE_DIGEST:
        raise RuntimeError("source semantic identity drift")
    if lock.get("layer_accounting") != EXPECTED_COUNTS:
        raise RuntimeError("source layer accounting drift")
    if (lock.get("building_ownership") or {}).get("ownership_filtered") != 62 or (lock.get("building_ownership") or {}).get("invalid_ownership_features") != 0:
        raise RuntimeError("building ownership accounting drift")
    for key in ("source_registration_authorized", "canonical_registration_authorized", "road_cell_mapping_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"):
        if lock.get(key) is not False:
            raise RuntimeError(f"source lock rail opened: {key}")

    source_path = repo_root / SOURCE_MANIFEST_PATH
    raw = source_path.read_bytes()
    if sha256_bytes(raw) != SOURCE_MANIFEST_SHA:
        raise RuntimeError("source manifest byte hash drift")
    source = json.loads(raw)
    if source.get("cell_id") != CELL_ID or source.get("crs") != CRS or source.get("bbox") != BBOX:
        raise RuntimeError("source manifest target drift")
    if source.get("promotion") != "source_only_no_runtime_mutation" or source.get("source_digest") != SOURCE_DIGEST:
        raise RuntimeError("source manifest provenance drift")
    counts = {name: int(row["features"]) for name, row in (source.get("layers") or {}).items()}
    if counts != EXPECTED_COUNTS:
        raise RuntimeError("source manifest layer accounting drift")

    index = read_json(repo_root / REGISTERED_INDEX_PATH)
    if int(index.get("registered_cell_count", -1)) != 2:
        raise RuntimeError("registered-cell baseline count drift")
    if any(str(row.get("cell_id")) == CELL_ID for row in index.get("entries", [])):
        raise RuntimeError("Bourse cell is already registered")
    for key in ("runtime_directory_scan_authorized", "road_crosswalk_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"):
        if index.get(key) is not False:
            raise RuntimeError(f"registered index rail opened: {key}")

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
        "maturity": {"gates": {"collisions": False, "heights": False, "performance": False, "photo_match": False, "runtime_geometry": False, "streaming": False, "terrain": False}, "state": "data_ready"},
        "provenance": {
            "authoritative_source_manifest": SOURCE_MANIFEST_PATH.as_posix(),
            "authoritative_source_manifest_sha256": SOURCE_MANIFEST_SHA,
            "license": "CC0-1.0",
            "municipality_assignment_policy": "retain_all_official_intersections_no_dominant_municipality_canonicalization",
            "municipality_intersections": intersections,
            "municipality_boundary_semantic_sha256": BOUNDARY_SEMANTIC_SHA,
            "primary": "UrbIS WFS / Paradigm",
            "source_records_present": True,
            "source_semantic_sha256": SOURCE_SEMANTIC_SHA,
        },
        "transport": {"rail_geometry_present": True, "service_simulation_validated": False, "tram_geometry_present": True},
        "uncertainties": [
            "cell crosses Anderlecht and Bruxelles; no single canonical municipality is inferred",
            "terrain and height evidence are not registered for this canonical cell",
            "runtime geometry, streaming, collisions, photo-match and performance remain unvalidated",
        ],
    }
    candidate_bytes = (json.dumps(candidate, indent=2, sort_keys=True) + "\n").encode("utf-8")
    candidate_sha = sha256_bytes(candidate_bytes)
    result = {
        "schema": "grand-bruxelles-bourse-canonical-manifest-candidate-review-v1",
        "status": "CANDIDATE_MEASURED_UNREGISTERED",
        "production_base_sha": production_base_sha,
        "target": {"cell_id": CELL_ID, "crs": CRS, "bbox": BBOX, "canonical_manifest_path": CANONICAL_PATH.as_posix(), "canonical_manifest_present": False},
        "source_evidence": {"lock_path": SOURCE_LOCK_PATH.as_posix(), "authority": lock["authority"], "license": lock["license"], "source_manifest_path": SOURCE_MANIFEST_PATH.as_posix(), "source_manifest_sha256": SOURCE_MANIFEST_SHA, "source_digest": SOURCE_DIGEST, "source_semantic_sha256": SOURCE_SEMANTIC_SHA},
        "municipality_boundary": {"semantic_sha256": BOUNDARY_SEMANTIC_SHA, "assignment_policy": "retain_all_official_intersections_no_dominant_municipality_canonicalization", "intersections": intersections},
        "candidate_manifest": {"artifact_filename": f"{CELL_ID}.candidate.json", "sha256": candidate_sha, "format": candidate["format"], "maturity_state": "data_ready", "all_maturity_gates_false": True},
        "registered_cell_index": {"path": REGISTERED_INDEX_PATH.as_posix(), "registered_cell_count": 2, "target_registered": False},
        "authorization": {"canonical_manifest_write": False, "registered_index_mutation": False, "road_to_cell_mapping": False, "runtime_mount": False, "rendered_geometry": False, "collision": False, "safe_spawn": False, "jouable_promotion": False},
        "next_action": "lock this measured candidate in a separate review file; do not write the canonical manifest or mutate the registered-cell index in this lot",
    }
    semantic = {k: v for k, v in result.items() if k != "production_base_sha"}
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
    out_candidate = Path(args.out_candidate); out_review = Path(args.out_review)
    out_candidate.parent.mkdir(parents=True, exist_ok=True); out_review.parent.mkdir(parents=True, exist_ok=True)
    out_candidate.write_bytes(candidate_bytes)
    out_review.write_text(json.dumps(review, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"BOURSE_CANONICAL_MANIFEST_CANDIDATE_MEASURED_UNREGISTERED: candidate_sha={review['candidate_manifest']['sha256']} semantic_sha={review['semantic_sha256']}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
