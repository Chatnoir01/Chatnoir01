#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

CELL_ID = "bxl-e147500-n169500-s500"
BBOX = [147500.0, 169500.0, 148000.0, 170000.0]
CRS = "EPSG:31370"
SOURCE_MANIFEST_SHA = "10aac9d4a2404ff23bb7d9af40b9e256b65aa6f25d33c7de1c1e3067244f43d2"
SOURCE_DIGEST = "06cc9e818a815bb00c74435a03f7d6ff8c7084010316abef0314fd376c210480"
SOURCE_SEMANTIC_SHA = "496e1049db535dbf3db2192066f41f60e9297e7b7931d9a8a427d6ffa378f8b0"
BOUNDARY_SEMANTIC_SHA = "4148e300ea5a81d60b5f16f0eab1186a3d646308cb7a4a4a1c5036b21e2bba8f"
EXPECTED_COUNTS = {"buildings": 362, "street_axes": 104, "street_surfaces": 283, "train_network": 361, "tram_network": 361}
EXPECTED_INTERSECTIONS = [
    {"niscode": "21013", "inspire_id": "https://databrussels.be/id/municipality/5000083", "coverage_ratio": 0.6455744665162007},
    {"niscode": "21001", "inspire_id": "https://databrussels.be/id/municipality/5000071", "coverage_ratio": 0.3516055345072097},
    {"niscode": "21004", "inspire_id": "https://databrussels.be/id/municipality/5000074", "coverage_ratio": 0.002819998976589587},
]

REVIEW_PATH = Path("data/provenance/anneessens_canonical_registration.review.json")
SOURCE_LOCK_PATH = Path("data/provenance/anneessens_urbis_source_cell.measurement.json")
PERSISTENCE_CONTRACT_PATH = Path("data/qa/anneessens_urbis_source_cell.persistence.contract.json")
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
    if boundary.get("status") != "HOLD_MUNICIPALITY_BOUNDARY_CELL":
        raise RuntimeError("municipality boundary status drift")
    if boundary.get("semantic_sha256") != BOUNDARY_SEMANTIC_SHA:
        raise RuntimeError("municipality boundary semantic identity drift")
    if boundary.get("assignment_policy") != "retain_all_official_intersections_no_dominant_municipality_canonicalization":
        raise RuntimeError("municipality assignment policy drift")
    rows = boundary.get("intersections") or []
    normalized = [{"niscode": str(r.get("niscode")), "inspire_id": str(r.get("inspire_id")), "coverage_ratio": float(r.get("coverage_ratio", -1))} for r in rows]
    if normalized != EXPECTED_INTERSECTIONS:
        raise RuntimeError(f"municipality boundary intersections drift: {normalized!r}")
    if abs(float(boundary.get("coverage_sum", -1)) - 1.0) > 1e-12:
        raise RuntimeError("municipality boundary coverage_sum drift")
    if abs(sum(r["coverage_ratio"] for r in normalized) - 1.0) > 1e-12:
        raise RuntimeError("municipality boundary intersections no longer sum to 1")
    return normalized

def validate_source_evidence(repo_root: Path, review: dict) -> tuple[dict, dict]:
    """Cross-check the merged semantic measurement, persistence contract and review.

    These are deliberately separate shipped schemas.  The semantic measurement
    does not carry lifecycle status/authority fields; those belong to the
    persistence contract and the canonical-registration review.  Treating the
    measurement as if it were the persistence contract made the RED-first
    candidate job fail before it could measure a candidate.
    """
    measurement = read_json(repo_root / SOURCE_LOCK_PATH)
    if measurement.get("schema") != "grand-bruxelles-urbis-source-cell-semantic-measurement-v1":
        raise RuntimeError("source semantic measurement schema drift")
    if measurement.get("cell_id") != CELL_ID or measurement.get("crs") != CRS or measurement.get("bbox") != BBOX:
        raise RuntimeError("source semantic measurement target drift")
    if measurement.get("source_semantic_sha256") != SOURCE_SEMANTIC_SHA or measurement.get("manifest_source_digest") != SOURCE_DIGEST:
        raise RuntimeError("source semantic identity drift")
    if measurement.get("manifest_sha256") != SOURCE_MANIFEST_SHA:
        raise RuntimeError("source semantic measurement manifest hash drift")
    measured_counts = {name: int(row.get("features", -1)) for name, row in (measurement.get("layers") or {}).items()}
    if measured_counts != EXPECTED_COUNTS:
        raise RuntimeError("source semantic measurement layer accounting drift")
    buildings = (measurement.get("layers") or {}).get("buildings") or {}
    if buildings.get("ownership_filtered") != 52 or buildings.get("invalid_ownership_features") != 0:
        raise RuntimeError("source semantic measurement building ownership drift")
    for key in ("registration_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"):
        if measurement.get(key) is not False:
            raise RuntimeError(f"source semantic measurement rail opened: {key}")

    persistence = read_json(repo_root / PERSISTENCE_CONTRACT_PATH)
    if persistence.get("schema") != "grand-bruxelles-urbis-source-cell-persistence-contract-v1":
        raise RuntimeError("source persistence contract schema drift")
    if persistence.get("cell_id") != CELL_ID or persistence.get("status") != "LOCKED_EXACT_SOURCE_ONLY_PERSISTED":
        raise RuntimeError("source cell is not locked/persisted")
    source_contract = persistence.get("source") or {}
    if source_contract.get("authority") != "Paradigm / Brussels-Capital Region" or source_contract.get("license") != "CC0-1.0":
        raise RuntimeError("source authority/license drift")
    if source_contract.get("crs") != CRS or source_contract.get("bbox") != BBOX:
        raise RuntimeError("source persistence target drift")
    artifact = persistence.get("locked_artifact") or {}
    if artifact.get("source_semantic_sha256") != SOURCE_SEMANTIC_SHA:
        raise RuntimeError("source persistence semantic identity drift")
    expected_manifest = (persistence.get("expected_files") or {}).get("manifest.json") or {}
    if expected_manifest.get("sha256") != SOURCE_MANIFEST_SHA:
        raise RuntimeError("source persistence manifest hash drift")
    accounting = persistence.get("accounting") or {}
    persistence_counts = {
        "buildings": int(accounting.get("buildings", -1)),
        "street_axes": int(accounting.get("street_axes", -1)),
        "street_surfaces": int(accounting.get("street_surfaces", -1)),
        "train_network": int(accounting.get("train_network", -1)),
        "tram_network": int(accounting.get("tram_network", -1)),
    }
    if persistence_counts != EXPECTED_COUNTS:
        raise RuntimeError("source persistence accounting drift")
    if accounting.get("buildings_ownership_filtered") != 52 or accounting.get("buildings_invalid_ownership") != 0:
        raise RuntimeError("source persistence building ownership drift")
    auth = persistence.get("authorization") or {}
    if auth.get("source_persistence") is not True:
        raise RuntimeError("source persistence authorization closed")
    for key in ("source_registration", "canonical_registration", "municipality_assignment", "road_to_cell_mapping", "runtime_directory_scan", "runtime_mount", "rendered_geometry", "collision", "safe_spawn", "jouable_promotion"):
        if auth.get(key) is not False:
            raise RuntimeError(f"source persistence downstream rail opened: {key}")

    review_source = review.get("source") or {}
    if review_source.get("authority") != source_contract["authority"] or review_source.get("license") != source_contract["license"]:
        raise RuntimeError("canonical review source authority/license drift")
    if review_source.get("source_semantic_sha256") != SOURCE_SEMANTIC_SHA or review_source.get("manifest_sha256") != SOURCE_MANIFEST_SHA or review_source.get("manifest_source_digest") != SOURCE_DIGEST:
        raise RuntimeError("canonical review source identity drift")
    if review_source.get("layer_accounting") != EXPECTED_COUNTS:
        raise RuntimeError("canonical review source layer accounting drift")
    if review_source.get("building_ownership") != {"ownership_filtered": 52, "invalid_ownership_features": 0}:
        raise RuntimeError("canonical review building ownership drift")
    return measurement, persistence

def build(repo_root: Path, production_base_sha: str) -> tuple[dict, dict, bytes]:
    if not re.fullmatch(r"[0-9a-f]{40}", production_base_sha):
        raise RuntimeError("production_base_sha must be a full lowercase SHA-1")
    if (repo_root / CANONICAL_PATH).exists():
        raise RuntimeError("canonical Anneessens manifest already exists; candidate-only phase must stop")
    review = read_json(repo_root / REVIEW_PATH)
    if review.get("schema") != "grand-bruxelles-anneessens-canonical-registration-review-v1":
        raise RuntimeError("canonical review schema drift")
    if review.get("status") != "READY_FOR_CANONICAL_MANIFEST_REVIEW_BOUNDARY_CELL":
        raise RuntimeError("canonical review is not ready for candidate generation")
    if review.get("cell_id") != CELL_ID or review.get("crs") != CRS or review.get("bbox") != BBOX:
        raise RuntimeError("canonical review target drift")
    for key in ("registration_authorized","road_cell_mapping_authorized","runtime_directory_scan_authorized","runtime_mount_authorized","rendered_geometry_authorized","collision_authorized","safe_spawn_authorized","jouable_promotion_authorized"):
        if review.get(key) is not False:
            raise RuntimeError(f"canonical review rail opened: {key}")
    intersections = validate_boundary(review.get("municipality_boundary") or {})
    measurement, persistence = validate_source_evidence(repo_root, review)
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
    if int(index.get("registered_cell_count", -1)) != 4:
        raise RuntimeError("registered-cell baseline count drift")
    if any(str(row.get("cell_id")) == CELL_ID for row in index.get("entries", [])):
        raise RuntimeError("Anneessens cell is already registered")
    for key in ("runtime_directory_scan_authorized","road_crosswalk_authorized","runtime_mount_authorized","rendered_geometry_authorized","collision_authorized","safe_spawn_authorized","jouable_promotion_authorized"):
        if index.get(key) is not False:
            raise RuntimeError(f"registered index rail opened: {key}")
    candidate = {
        "bbox": BBOX,
        "cell_id": CELL_ID,
        "collisions": {"status": "not_validated"},
        "crs": CRS,
        "format": "grand-bruxelles-cell-maturity-v1",
        "geometry": {"authoritative_geometry_ready": True,"layer_feature_counts": EXPECTED_COUNTS,"layers": ["buildings","street_surfaces","street_axes","tram_network","train_network"],"source_digest": SOURCE_DIGEST,"source_manifest": SOURCE_MANIFEST_PATH.as_posix()},
        "maturity": {"gates": {"collisions": False,"heights": False,"performance": False,"photo_match": False,"runtime_geometry": False,"streaming": False,"terrain": False},"state": "data_ready"},
        "provenance": {"authoritative_source_manifest": SOURCE_MANIFEST_PATH.as_posix(),"authoritative_source_manifest_sha256": SOURCE_MANIFEST_SHA,"license": "CC0-1.0","municipality_assignment_policy": "retain_all_official_intersections_no_dominant_municipality_canonicalization","municipality_intersections": intersections,"municipality_boundary_semantic_sha256": BOUNDARY_SEMANTIC_SHA,"primary": "UrbIS WFS / Paradigm","source_records_present": True,"source_semantic_sha256": SOURCE_SEMANTIC_SHA},
        "transport": {"rail_geometry_present": True,"service_simulation_validated": False,"tram_geometry_present": True},
        "uncertainties": ["cell crosses Saint-Gilles, Anderlecht and Bruxelles; no single canonical municipality is inferred","terrain evidence is not registered for this canonical cell","height evidence is not registered for this canonical cell","runtime geometry, streaming, collisions, photo-match and performance remain unvalidated"],
        "terrain": {"status": "not_registered","source": "no authoritative terrain evidence registered for this canonical cell"},
        "heights": {"status": "not_registered","reason": "no authoritative height evidence is registered for this canonical cell"},
        "photo_match": {"required": False,"status": "not_validated","open_major_mismatches": 0},
        "performance": {"status": "not_measured_as_streamed_cell","budget_pass": False},
    }
    candidate_bytes = (json.dumps(candidate, indent=2, sort_keys=True) + "\n").encode("utf-8")
    candidate_sha = sha256_bytes(candidate_bytes)
    source_contract = persistence["source"]
    result = {
        "schema": "grand-bruxelles-anneessens-canonical-manifest-candidate-review-v1",
        "status": "CANDIDATE_MEASURED_UNREGISTERED",
        "production_base_sha": production_base_sha,
        "target": {"cell_id": CELL_ID,"crs": CRS,"bbox": BBOX,"canonical_manifest_path": CANONICAL_PATH.as_posix(),"canonical_manifest_present": False},
        "source_evidence": {"lock_path": SOURCE_LOCK_PATH.as_posix(),"persistence_contract_path": PERSISTENCE_CONTRACT_PATH.as_posix(),"authority": source_contract["authority"],"license": source_contract["license"],"source_manifest_path": SOURCE_MANIFEST_PATH.as_posix(),"source_manifest_sha256": SOURCE_MANIFEST_SHA,"source_digest": SOURCE_DIGEST,"source_semantic_sha256": measurement["source_semantic_sha256"],"layer_accounting": EXPECTED_COUNTS,"building_ownership": {"ownership_filtered": 52,"invalid_ownership_features": 0}},
        "municipality_boundary": {"semantic_sha256": BOUNDARY_SEMANTIC_SHA,"assignment_policy": "retain_all_official_intersections_no_dominant_municipality_canonicalization","intersections": intersections},
        "candidate_manifest": {"artifact_filename": f"{CELL_ID}.candidate.json","sha256": candidate_sha,"format": candidate["format"],"maturity_state": "data_ready","all_maturity_gates_false": True},
        "registered_cell_index": {"path": REGISTERED_INDEX_PATH.as_posix(),"registered_cell_count": 4,"target_registered": False},
        "authorization": {"canonical_manifest_write": False,"registered_index_mutation": False,"road_to_cell_mapping": False,"runtime_mount": False,"rendered_geometry": False,"collision": False,"safe_spawn": False,"jouable_promotion": False},
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
    print(f"ANNEESSENS_CANONICAL_MANIFEST_CANDIDATE_MEASURED_UNREGISTERED: candidate_sha={review['candidate_manifest']['sha256']} semantic_sha={review['semantic_sha256']}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())