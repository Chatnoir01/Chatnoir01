#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def load_obj(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise RuntimeError(f"required input missing: {path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"input must be an object: {path}")
    return value


def require_sha(value: Any, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise RuntimeError(f"{label} SHA-256 missing or malformed")
    return value


def require_closed(value: Any, label: str) -> None:
    if not isinstance(value, dict):
        raise RuntimeError(f"{label} must be an object")
    for key, item in value.items():
        if (key.endswith("_authorized") or key.endswith("_approved")) and item is not False:
            raise RuntimeError(f"{label} rail widened: {key}")


def bbox4(value: Any, label: str) -> tuple[float, float, float, float]:
    if not isinstance(value, list) or len(value) != 4:
        raise RuntimeError(f"{label} bbox must contain four values")
    result = tuple(float(v) for v in value)
    if not (result[0] < result[2] and result[1] < result[3]):
        raise RuntimeError(f"{label} bbox invalid: {result}")
    return result


def rects_intersect(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


def grid_id_from_bbox(bbox: tuple[float, float, float, float]) -> str:
    if bbox[2] - bbox[0] != 500.0 or bbox[3] - bbox[1] != 500.0:
        raise RuntimeError(f"registered bbox is not an exact 500m cell: {bbox}")
    return f"E{int(bbox[0])}_N{int(bbox[1])}"


def semantic_sha(value: dict[str, Any]) -> str:
    basis = dict(value)
    basis.pop("semantic_sha256", None)
    basis.pop("production_base_sha", None)
    return hashlib.sha256(
        json.dumps(basis, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def build_report(
    coverage_path: Path,
    cells_path: Path,
    crosswalk_path: Path,
    production_base_sha: str,
) -> dict[str, Any]:
    coverage = load_obj(coverage_path)
    cells = load_obj(cells_path)
    crosswalk = load_obj(crosswalk_path)

    if coverage.get("schema") != "grand-bruxelles-road-cell-coverage-candidates-v2":
        raise RuntimeError("unsupported road coverage schema")
    if coverage.get("status") != "DISCOVERED_SOURCE_ONLY":
        raise RuntimeError("road coverage must remain DISCOVERED_SOURCE_ONLY")
    require_closed(coverage, "road coverage")

    if cells.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise RuntimeError("unsupported registered-cell index schema")
    if cells.get("destination_readiness") != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise RuntimeError("registered-cell readiness widened")
    require_closed(cells, "registered-cell index")

    if crosswalk.get("schema") != "grand-bruxelles-road-registered-cell-crosswalk-v1":
        raise RuntimeError("unsupported road crosswalk schema")
    if crosswalk.get("destination_readiness") != "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY":
        raise RuntimeError("road crosswalk readiness widened")
    require_closed(crosswalk, "road crosswalk")

    if crosswalk.get("coverage_semantic_sha256") != coverage.get("semantic_sha256"):
        raise RuntimeError("crosswalk does not bind current road coverage semantic")
    if crosswalk.get("road_semantic_sha256") != coverage.get("road_semantic_sha256"):
        raise RuntimeError("crosswalk does not bind current road semantic")
    if crosswalk.get("registered_cell_index_semantic_sha256") != cells.get("semantic_sha256"):
        raise RuntimeError("crosswalk does not bind current registered-cell semantic")

    road_bbox = bbox4(coverage.get("road_lambert72_bbox"), "road source")
    candidate_by_bbox: dict[tuple[float, float, float, float], dict[str, Any]] = {}
    for candidate in coverage.get("candidates") or []:
        if not isinstance(candidate, dict):
            raise RuntimeError("candidate must be an object")
        require_closed(candidate, "road coverage candidate")
        b = bbox4(candidate.get("bbox"), "candidate")
        candidate_by_bbox[b] = candidate
    if len(candidate_by_bbox) != coverage.get("candidate_cell_count"):
        raise RuntimeError("candidate-cell count mismatch")

    mapped_cell_ids = {row.get("cell_id") for row in (crosswalk.get("rows") or [])}
    unmatched_from_crosswalk = set(crosswalk.get("unmatched_registered_cell_ids") or [])
    registered_entries = cells.get("entries") or []
    if len(registered_entries) != cells.get("registered_cell_count"):
        raise RuntimeError("registered-cell count mismatch")

    gaps: list[dict[str, Any]] = []
    for entry in registered_entries:
        if not isinstance(entry, dict) or entry.get("evidence_only") is not True:
            raise RuntimeError("registered cell must remain evidence-only")
        require_closed(entry, "registered cell")
        cell_id = entry.get("cell_id")
        if not isinstance(cell_id, str) or not cell_id:
            raise RuntimeError("registered cell id missing")
        if cell_id in mapped_cell_ids:
            continue

        b = bbox4(entry.get("bbox"), "registered cell")
        grid_id = grid_id_from_bbox(b)
        candidate = candidate_by_bbox.get(b)
        intersects = rects_intersect(b, road_bbox)
        if candidate is None:
            reason = "SOURCE_ROAD_BBOX_DISJOINT" if not intersects else "NO_CANDIDATE_WITHIN_SOURCE_BBOX"
            mapped_road_count = 0
        else:
            reason = "CANDIDATE_PRESENT_BUT_NO_UNIQUE_ROAD_MAPPING"
            mapped_road_count = int(candidate.get("road_count") or 0)

        east_gap = max(0.0, b[0] - road_bbox[2], road_bbox[0] - b[2])
        north_gap = max(0.0, b[1] - road_bbox[3], road_bbox[1] - b[3])
        gaps.append({
            "cell_id": cell_id,
            "grid_cell_id": grid_id,
            "bbox": list(b),
            "reason": reason,
            "candidate_present": candidate is not None,
            "mapped_road_count": mapped_road_count,
            "east_gap_m": east_gap,
            "north_gap_m": north_gap,
            "minimum_source_extension_m": math.hypot(east_gap, north_gap),
        })

    gap_ids = {g["cell_id"] for g in gaps}
    if gap_ids != unmatched_from_crosswalk:
        raise RuntimeError(
            f"gap/crosswalk unmatched mismatch: audit={sorted(gap_ids)} crosswalk={sorted(unmatched_from_crosswalk)}"
        )

    result: dict[str, Any] = {
        "schema": "grand-bruxelles-registered-cell-road-coverage-gaps-v1",
        "status": "SOURCE_EXTENSION_REQUIRED_EVIDENCE_ONLY",
        "production_base_sha": production_base_sha,
        "inputs": {
            "road_coverage_path": "data/city_machine/road_cell_coverage_candidates.json",
            "road_coverage_semantic_sha256": require_sha(coverage.get("semantic_sha256"), "road coverage semantic"),
            "road_semantic_sha256": require_sha(coverage.get("road_semantic_sha256"), "road semantic"),
            "registered_cell_index_path": "data/provenance/brussels_registered_cell_manifest_index.json",
            "registered_cell_index_semantic_sha256": require_sha(cells.get("semantic_sha256"), "registered-cell semantic"),
            "road_crosswalk_path": "data/provenance/brussels_road_registered_cell_crosswalk.json",
            "road_crosswalk_semantic_sha256": require_sha(crosswalk.get("semantic_sha256"), "road crosswalk semantic"),
        },
        "road_source": {
            "provider": coverage.get("road_source_provider"),
            "license": coverage.get("road_source_license"),
            "source_path": coverage.get("road_source"),
            "source_sha256": require_sha(coverage.get("road_source_sha256"), "road source"),
            "lambert72_bbox": list(road_bbox),
            "road_count": int(coverage.get("road_count")),
            "road_point_count": int(coverage.get("road_point_count")),
            "candidate_cell_count": int(coverage.get("candidate_cell_count")),
        },
        "coverage_accounting": {
            "registered_cell_count": int(cells.get("registered_cell_count")),
            "mapped_registered_cell_count": len(mapped_cell_ids),
            "unmatched_registered_cell_count": len(gaps),
            "all_unmatched_are_source_bbox_disjoint": all(g["reason"] == "SOURCE_ROAD_BBOX_DISJOINT" for g in gaps),
        },
        "gaps": sorted(gaps, key=lambda g: g["cell_id"]),
        "authorization": {
            "source_refresh_authorized": False,
            "road_cell_mapping_authorized": False,
            "runtime_directory_scan_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        },
    }
    result["semantic_sha256"] = semantic_sha(result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--coverage", type=Path, required=True)
    parser.add_argument("--cells", type=Path, required=True)
    parser.add_argument("--crosswalk", type=Path, required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = build_report(args.coverage, args.cells, args.crosswalk, args.production_base_sha)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        print(f"REGISTERED_CELL_ROAD_COVERAGE_GAP_RED: {exc}")
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        "REGISTERED_CELL_ROAD_COVERAGE_GAP_OK "
        f"registered={result['coverage_accounting']['registered_cell_count']} "
        f"mapped={result['coverage_accounting']['mapped_registered_cell_count']} "
        f"unmatched={result['coverage_accounting']['unmatched_registered_cell_count']} "
        f"semantic_sha256={result['semantic_sha256']} rails_closed=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
