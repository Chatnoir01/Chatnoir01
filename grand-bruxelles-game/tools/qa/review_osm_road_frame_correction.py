#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
from pathlib import Path

import pyproj
from pyproj import Transformer

SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_sha(obj) -> str:
    return sha256_bytes(json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))


def require_projection_version(actual: str, expected: str) -> None:
    assert actual == expected, f"pyproj version mismatch: actual={actual} expected={expected}"


def require_git_sha(value: str, label: str) -> None:
    assert SHA_RE.fullmatch(value or "") is not None, f"{label} malformed: {value}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--live-main-sha")
    parser.add_argument("--output")
    args = parser.parse_args()

    root = Path(args.repo_root).resolve()
    contract = json.loads((root / args.contract).read_text())
    assert contract["schema"] == "grand-bruxelles-osm-road-frame-correction-review-v1"
    assert contract["status"] == "READY_FOR_FRAME_CORRECTION_REVIEW_SOURCE_ORIGIN"
    require_git_sha(contract["production_base_sha"], "production evidence base")
    if args.live_main_sha:
        require_git_sha(args.live_main_sha, "live main")

    source = contract["source"]
    source_path = root / source["path"]
    source_bytes = source_path.read_bytes()
    assert sha256_bytes(source_bytes) == source["sha256"]
    source_json = json.loads(source_bytes)
    assert source_json["source"] == source["provider"]
    assert source_json["license"] == source["license"]
    assert source_json["origin"] == {
        "lat": source["declared_origin_wgs84"]["lat"],
        "lon": source["declared_origin_wgs84"]["lon"],
    }

    recon = contract["reconciliation"]
    recon_json = json.loads((root / recon["contract"]).read_text())
    locked = recon_json["locked_measurement"]
    assert locked["semantic_sha256"] == recon["semantic_sha256"]
    assert locked["accounting"]["duplicate_osm_way_count"] == recon["duplicate_osm_way_count"]
    assert locked["accounting"]["duplicate_class_mismatch_count"] == recon["duplicate_class_mismatch_count"]
    assert locked["historical_frame_fit"]["worst_max_corresponding_residual_m"] == recon["historical_worst_residual_m"]
    assert locked["projected_source_origin_frame_fit"]["worst_max_corresponding_residual_m"] == recon["candidate_worst_residual_m"]
    assert locked["projected_source_origin_frame_fit"]["worst_rigid_delta_deviation_m"] == recon["candidate_worst_rigid_delta_deviation_m"]
    assert recon_json["review_verdict"]["projected_source_origin_frame_is_supported_candidate"] is True
    assert recon_json["review_verdict"]["projected_source_origin_frame_authorized_for_production"] is False

    candidate = contract["candidate_frame"]
    require_projection_version(pyproj.__version__, candidate["pyproj_version"])
    transformer = Transformer.from_crs("EPSG:4326", "EPSG:31370", always_xy=True)
    easting, northing = transformer.transform(source["declared_origin_wgs84"]["lon"], source["declared_origin_wgs84"]["lat"])
    projected = [round(easting, 6), round(northing, 6)]
    assert projected == [candidate["origin_easting_m"], candidate["origin_northing_m"]], projected
    assert candidate["crs"] == "EPSG:31370"
    assert candidate["formula"] == "E=origin_easting_m+x;N=origin_northing_m-z"

    acceptance = contract["acceptance"]
    historical = recon["historical_worst_residual_m"]
    proposed = recon["candidate_worst_residual_m"]
    improvement = historical / proposed
    assert acceptance["historical_frame_rejected"] is True
    assert acceptance["candidate_supported"] is True
    assert historical >= acceptance["min_historical_worst_residual_m"]
    assert proposed <= acceptance["max_candidate_worst_residual_m"]
    assert improvement >= acceptance["min_improvement_ratio"]
    assert all(value is False for value in contract["authorization"].values())

    semantic_obj = {k: v for k, v in contract.items() if k not in {"production_base_sha", "review_semantic_sha256"}}
    assert canonical_sha(semantic_obj) == contract["review_semantic_sha256"]

    result = {
        "schema": "grand-bruxelles-osm-road-frame-correction-review-result-v1",
        "status": contract["status"],
        "production_evidence_base_sha": contract["production_base_sha"],
        "live_main_sha": args.live_main_sha,
        "source_sha256": source["sha256"],
        "source_origin_wgs84": source["declared_origin_wgs84"],
        "projection_engine": {"name": "pyproj", "version": pyproj.__version__},
        "candidate_origin_epsg31370": projected,
        "duplicate_osm_way_count": recon["duplicate_osm_way_count"],
        "historical_worst_residual_m": historical,
        "candidate_worst_residual_m": proposed,
        "improvement_ratio": round(improvement, 6),
        "review_semantic_sha256": contract["review_semantic_sha256"],
        "authorization": dict(contract["authorization"]),
        "production_frame_update_authorized": False,
        "source_merge_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_mount_authorized": False,
        "jouable_promotion_authorized": False,
    }
    if args.output:
        Path(args.output).write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print("OSM_ROAD_FRAME_CORRECTION_REVIEW_OK", json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
