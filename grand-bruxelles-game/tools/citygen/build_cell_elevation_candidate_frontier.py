#!/usr/bin/env python3
"""Derive the next fail-closed CityGen elevation frontier for one Brussels cell.

This deliberately does not invent terrain resolution or building heights. It turns
validated source-value evidence into an explicit next-gate contract so autonomous
CityGen can advance evidence maturity without accidentally promoting runtime data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-cell-elevation-candidate-frontier-v1"
VALUE_FORMAT = "grand-bruxelles-cell-elevation-value-evidence-v1"
PACKAGE_FORMAT = "grand-bruxelles-cell-candidate-package-v1"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _finite_stat(stats: dict[str, Any], key: str) -> float | None:
    value = stats.get(key)
    if not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if value == value and value not in (float("inf"), float("-inf")) else None


def build(value_evidence_path: Path, candidate_package_path: Path | None = None) -> dict[str, Any]:
    evidence = _read(value_evidence_path)
    if evidence.get("format") != VALUE_FORMAT or evidence.get("crs") != "EPSG:31370":
        raise ValueError("unsupported elevation value evidence or CRS")
    cell_id = evidence.get("cell_id")
    bbox = evidence.get("bbox")
    if not isinstance(cell_id, str) or not cell_id.startswith("bxl-"):
        raise ValueError("invalid elevation evidence cell id")
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise ValueError("elevation evidence bbox missing")

    package: dict[str, Any] | None = None
    building_count = 0
    package_digest = None
    if candidate_package_path is not None:
        package = _read(candidate_package_path)
        if package.get("format") != PACKAGE_FORMAT or package.get("crs") != "EPSG:31370":
            raise ValueError("unsupported candidate package or CRS")
        if package.get("cell_id") != cell_id:
            raise ValueError("cell identity mismatch between elevation evidence and candidate package")
        building_count = int((package.get("summary") or {}).get("valid_buildings", 0))
        if building_count < 0:
            raise ValueError("candidate package valid_buildings cannot be negative")
        package_digest = package.get("package_digest")

    terrain_ready = evidence.get("terrain_source_evidence_ready") is True
    height_pair_ready = evidence.get("height_source_pair_ready") is True
    failures = [str(value) for value in (evidence.get("quality_failures") or [])]

    dtm = evidence.get("dtm") or {}
    delta = evidence.get("dsm_minus_dtm") or {}
    terrain = {
        "source_ready": terrain_ready,
        "runtime_approved": False,
        "resolution_m": None,
        "source_valid_ratio": _finite_stat(dtm, "valid_ratio"),
        "source_p50_m": _finite_stat(dtm, "p50_m"),
        "source_span_m": _finite_stat(dtm, "span_m"),
        "next_gate": "measure_terrain_lod_reconstruction_error" if terrain_ready else "resolve_terrain_source_quality_blockers",
        "promotion_policy": "no_runtime_terrain_until_lod_error_seams_normals_collision_and_performance_are_validated",
    }
    heights = {
        "source_pair_ready": height_pair_ready,
        "runtime_approved": False,
        "candidate_height_count": 0,
        "building_sample_target_count": building_count if height_pair_ready else 0,
        "source_pair_valid_ratio": _finite_stat(delta, "valid_ratio"),
        "source_delta_p50_m": _finite_stat(delta, "p50_m"),
        "source_delta_p95_m": _finite_stat(delta, "p95_m"),
        "next_gate": "sample_per_building_dsm_minus_dtm_and_cross_validate" if height_pair_ready else "resolve_height_source_pair_blockers",
        "promotion_policy": "no_building_height_candidate_until_per_building_sampling_and_independent_secondary_validation",
    }

    blockers = list(failures)
    if not terrain_ready:
        blockers.append("terrain_source_evidence_not_ready")
    if not height_pair_ready:
        blockers.append("height_source_pair_not_ready")
    if height_pair_ready and candidate_package_path is None:
        blockers.append("authoritative_building_candidate_package_missing")
        heights["building_sample_target_count"] = 0
        heights["next_gate"] = "provide_authoritative_building_candidate_package"

    if terrain_ready and height_pair_ready and candidate_package_path is not None:
        next_action = "assess_terrain_lod_and_building_height_samples"
    elif terrain_ready:
        next_action = "assess_terrain_lod_only"
    elif height_pair_ready and candidate_package_path is not None:
        next_action = "sample_building_heights_only"
    else:
        next_action = "resolve_elevation_quality_blockers"

    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": "EPSG:31370",
        "bbox": bbox,
        "source_evidence_digest": evidence.get("evidence_digest"),
        "candidate_package_digest": package_digest,
        "terrain": terrain,
        "heights": heights,
        "blockers": sorted(set(blockers)),
        "next_action": next_action,
        "runtime_promotion_allowed": False,
        "maturity_effect": {
            "terrain_gate": False,
            "heights_gate": False,
            "reason": "candidate_frontier_only_measured_runtime_and_secondary_validation_gates_remain_required",
        },
    }
    result["frontier_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--value-evidence", type=Path, required=True)
    parser.add_argument("--candidate-package", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.value_evidence, args.candidate_package)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CELL_ELEVATION_CANDIDATE_FRONTIER_OK", result["cell_id"], result["next_action"], result["frontier_digest"])


if __name__ == "__main__":
    main()
