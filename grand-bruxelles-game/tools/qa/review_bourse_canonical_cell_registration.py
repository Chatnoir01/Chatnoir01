#!/usr/bin/env python3
"""Review Bourse canonical-cell registration readiness without registering it.

Consumes only persisted, content-addressed repository evidence. It never queries
remote services and never writes a canonical manifest or registered-cell index.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

CELL_ID = "bxl-e147500-n170000-s500"
BBOX = [147500.0, 170000.0, 148000.0, 170500.0]
SOURCE_REL = Path("data/urbis/remaining_brussels/cells") / CELL_ID
SOURCE_LOCK = Path("data/provenance/bourse_urbis_source_cell.measurement.json")
MUNICIPAL_LOCK = Path("data/provenance/bourse_road_cell_municipality.measurement.json")
REGISTERED_INDEX = Path("data/provenance/brussels_registered_cell_manifest_index.json")
CANONICAL_MANIFEST = Path("data/cell_manifests") / f"{CELL_ID}.json"

EXPECTED_SOURCE_SEMANTIC = "f88ece4309964ed9939de100424716c90a59409db66924332abb8ea00ff652e0"
EXPECTED_MUNICIPAL_SEMANTIC = "c01208a81d61d51492b928f7381991e0fdacd68f62e8ac7a77be8ba08f46ff63"
EXPECTED_COUNTS = {
    "buildings": 799,
    "street_axes": 76,
    "street_surfaces": 310,
    "train_network": 14,
    "tram_network": 14,
}
EXPECTED_MUNICIPALITIES = {
    "21001": ("https://databrussels.be/id/municipality/5000071", 208021.26572820908),
    "21004": ("https://databrussels.be/id/municipality/5000074", 41978.734271790905),
}
FORBIDDEN_TRUE = (
    "source_registration_authorized",
    "canonical_registration_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def require_false(payload: dict, keys=FORBIDDEN_TRUE) -> None:
    for key in keys:
        if payload.get(key) is not False:
            raise RuntimeError(f"{key} must remain explicitly false")


def build_review(game_root: Path, production_base_sha: str) -> dict:
    source_dir = game_root / SOURCE_REL
    source_manifest_path = source_dir / "manifest.json"
    maturity_path = source_dir / "maturity.json"
    source_lock_path = game_root / SOURCE_LOCK
    municipal_lock_path = game_root / MUNICIPAL_LOCK
    registered_index_path = game_root / REGISTERED_INDEX

    for path in (source_manifest_path, maturity_path, source_lock_path, municipal_lock_path, registered_index_path):
        if not path.is_file():
            raise RuntimeError(f"required evidence missing: {path.relative_to(game_root)}")

    source_manifest = load(source_manifest_path)
    maturity = load(maturity_path)
    source_lock = load(source_lock_path)
    municipal_lock = load(municipal_lock_path)
    registered = load(registered_index_path)

    if source_lock.get("status") != "LOCKED_EXACT_SOURCE_ONLY_PERSISTED":
        raise RuntimeError("Bourse source cell is not exact-persisted")
    if source_lock.get("cell_id") != CELL_ID or source_lock.get("crs") != "EPSG:31370" or source_lock.get("bbox") != BBOX:
        raise RuntimeError("Bourse source-cell identity/CRS/bbox drift")
    if source_lock.get("authority") != "Paradigm / Brussels-Capital Region" or source_lock.get("license") != "CC0-1.0":
        raise RuntimeError("Bourse source authority/license drift")
    if source_lock.get("source_semantic_sha256") != EXPECTED_SOURCE_SEMANTIC:
        raise RuntimeError("Bourse source semantic digest drift")
    if source_lock.get("layer_accounting") != EXPECTED_COUNTS:
        raise RuntimeError("Bourse source accounting drift")
    if source_lock.get("building_ownership") != {"ownership_filtered": 62, "invalid_ownership_features": 0}:
        raise RuntimeError("Bourse building ownership accounting drift")
    require_false(source_lock)

    if sha256(source_manifest_path) != source_lock.get("manifest_sha256"):
        raise RuntimeError("persisted source manifest byte hash drift")
    if sha256(maturity_path) != source_lock.get("maturity_sha256"):
        raise RuntimeError("persisted maturity byte hash drift")
    if source_manifest.get("cell_id") != CELL_ID or source_manifest.get("crs") != "EPSG:31370" or source_manifest.get("bbox") != BBOX:
        raise RuntimeError("persisted source manifest identity drift")
    if source_manifest.get("promotion") != "source_only_no_runtime_mutation":
        raise RuntimeError("persisted source manifest promotion drift")
    for layer, count in EXPECTED_COUNTS.items():
        if int(source_manifest["layers"][layer]["features"]) != count:
            raise RuntimeError(f"persisted layer count drift: {layer}")
        raw = source_dir / source_manifest["layers"][layer]["file"]
        if not raw.is_file():
            raise RuntimeError(f"persisted raw layer missing: {layer}")
        expected_raw = source_lock["layers"][layer]["raw_forensic_sha256"]
        if sha256(raw) != expected_raw:
            raise RuntimeError(f"persisted raw layer byte hash drift: {layer}")

    if maturity.get("cell_id") != CELL_ID or maturity.get("crs") != "EPSG:31370" or maturity.get("bbox") != BBOX:
        raise RuntimeError("Bourse maturity identity drift")
    if maturity.get("maturity", {}).get("state") != "data_ready":
        raise RuntimeError("Bourse source cell is not data_ready")
    gates = maturity.get("maturity", {}).get("gates", {})
    for key in ("runtime_geometry", "collisions", "streaming", "terrain", "heights", "photo_match", "performance"):
        if gates.get(key) is not False:
            raise RuntimeError(f"maturity gate unexpectedly open: {key}")

    if municipal_lock.get("status") != "LOCKED_SOURCE_ONLY_BOUNDARY_HOLD" or municipal_lock.get("semantic_sha256") != EXPECTED_MUNICIPAL_SEMANTIC:
        raise RuntimeError("Bourse municipality boundary proof drift")
    require_false(municipal_lock, (
        "registration_authorized", "road_cell_mapping_authorized", "runtime_mount_authorized",
        "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ))
    coverage = municipal_lock["stable_measurement"]["municipality_coverage"]
    if coverage.get("status") != "HOLD_MUNICIPALITY_BOUNDARY_CELL" or coverage.get("municipality_id") is not None or coverage.get("municipality_niscode") is not None:
        raise RuntimeError("boundary cell must not collapse to a single municipality")
    if abs(float(coverage.get("intersection_coverage_sum", 0.0)) - 1.0) > 1e-12:
        raise RuntimeError("municipality coverage must sum exactly to one within tolerance")
    intersections = coverage.get("intersections", [])
    if len(intersections) != 2:
        raise RuntimeError("Bourse boundary proof must retain exactly two municipalities")
    seen = set()
    for item in intersections:
        nis = str(item["properties"]["NISCODE"])
        seen.add(nis)
        expected_id, expected_area = EXPECTED_MUNICIPALITIES.get(nis, (None, None))
        if expected_id is None or item.get("municipality_id") != expected_id:
            raise RuntimeError(f"unexpected municipality identity: {nis}")
        if abs(float(item["intersection_area_m2"]) - expected_area) > 1e-6:
            raise RuntimeError(f"municipality area drift: {nis}")
    if seen != set(EXPECTED_MUNICIPALITIES):
        raise RuntimeError("municipality set drift")

    registered_ids = {entry.get("cell_id") for entry in registered.get("entries", [])}
    if CELL_ID in registered_ids:
        raise RuntimeError("Bourse is already registered; this review phase is obsolete")
    if (game_root / CANONICAL_MANIFEST).exists():
        raise RuntimeError("Bourse canonical manifest already exists; this review phase is obsolete")
    for key in ("road_crosswalk_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"):
        if registered.get(key) is not False:
            raise RuntimeError(f"registered-cell index rail unexpectedly open: {key}")

    review = {
        "schema": "grand-bruxelles-bourse-canonical-registration-review-v1",
        "status": "READY_FOR_CANONICAL_MANIFEST_REVIEW_BOUNDARY_CELL",
        "production_base_sha": production_base_sha,
        "cell_id": CELL_ID,
        "crs": "EPSG:31370",
        "bbox": BBOX,
        "source": {
            "provider": source_lock["authority"],
            "service": source_lock["service"],
            "license": source_lock["license"],
            "revision": source_lock["revision"],
            "source_artifact": source_lock["source_artifact"],
            "source_semantic_sha256": EXPECTED_SOURCE_SEMANTIC,
            "manifest_sha256": source_lock["manifest_sha256"],
            "layer_accounting": EXPECTED_COUNTS,
            "building_ownership": source_lock["building_ownership"],
        },
        "municipality_boundary": {
            "semantic_sha256": EXPECTED_MUNICIPAL_SEMANTIC,
            "assignment_policy": "retain_all_official_intersections_no_dominant_municipality_canonicalization",
            "intersections": [
                {"niscode": "21001", "inspire_id": EXPECTED_MUNICIPALITIES["21001"][0], "intersection_area_m2": EXPECTED_MUNICIPALITIES["21001"][1], "coverage_ratio": 0.8320850629128363},
                {"niscode": "21004", "inspire_id": EXPECTED_MUNICIPALITIES["21004"][0], "intersection_area_m2": EXPECTED_MUNICIPALITIES["21004"][1], "coverage_ratio": 0.16791493708716362},
            ],
        },
        "registered_cell_count_before_review": int(registered["registered_cell_count"]),
        "canonical_manifest_present": False,
        "registration_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_directory_scan_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
        "next_action": "separate canonical-manifest candidate generation preserving both municipality intersections; do not mutate registered-cell index in this review lot",
    }
    canonical = json.dumps(review, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    review["semantic_sha256"] = hashlib.sha256(canonical).hexdigest()
    return review


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    game_root = args.repo_root / "grand-bruxelles-game"
    review = build_review(game_root, args.production_base_sha)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(review, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BOURSE_CANONICAL_REGISTRATION_REVIEW_OK: status={review['status']} semantic_sha256={review['semantic_sha256']}")

if __name__ == "__main__":
    main()
