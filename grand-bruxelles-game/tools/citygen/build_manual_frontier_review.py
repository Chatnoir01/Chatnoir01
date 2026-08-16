#!/usr/bin/env python3
"""Package CityGen manual-frontier evidence without promoting runtime state.

Consumes per-building DSM-DTM height candidates and DTM LOD evidence from the same
cell, validates their fail-closed contracts, and emits a compact review package. This
is evidence packaging only: secondary independent height validation and all terrain
runtime gates remain mandatory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-citygen-manual-frontier-review-v1"
HEIGHT_FORMAT = "grand-bruxelles-cell-building-height-candidates-v1"
TERRAIN_FORMAT = "grand-bruxelles-cell-dtm-lod-evidence-v1"
CRS = "EPSG:31370"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def build(height_candidates_path: Path, terrain_lod_path: Path) -> dict[str, Any]:
    heights = _read(height_candidates_path)
    terrain = _read(terrain_lod_path)

    if heights.get("format") != HEIGHT_FORMAT or heights.get("crs") != CRS:
        raise ValueError("unsupported building height candidate evidence")
    if terrain.get("format") != TERRAIN_FORMAT or terrain.get("crs") != CRS:
        raise ValueError("unsupported terrain LOD evidence")
    cell_id = heights.get("cell_id")
    if not isinstance(cell_id, str) or terrain.get("cell_id") != cell_id:
        raise ValueError("manual frontier cell identity mismatch")
    if heights.get("runtime_promotion_allowed") is not False or int(heights.get("runtime_approved_count", 0)) != 0:
        raise ValueError("height candidate evidence must explicitly forbid runtime promotion")
    if terrain.get("runtime_approved") is not False:
        raise ValueError("terrain LOD evidence must remain runtime-unapproved")

    selection = terrain.get("selection") or {}
    if not isinstance(selection, dict):
        raise ValueError("terrain LOD selection is missing")
    if selection.get("runtime_approved") is not False:
        raise ValueError("terrain LOD selection must remain runtime-unapproved")

    buildings = heights.get("buildings") or []
    if not isinstance(buildings, list):
        raise ValueError("height candidate building list is invalid")

    candidates = []
    flagged = []
    for row in buildings:
        if not isinstance(row, dict):
            continue
        candidate = row.get("candidate_height_m")
        if candidate is None:
            continue
        if row.get("runtime_approved") is not False or row.get("secondary_validation_required") is not True:
            raise ValueError("height candidate bypassed secondary-validation contract")
        building_id = str(row.get("building_id"))
        flags = list((row.get("height_stats") or {}).get("review_flags") or [])
        candidates.append({
            "building_id": building_id,
            "candidate_height_m": float(candidate),
            "confidence": str(row.get("confidence")),
            "review_flags": sorted(str(flag) for flag in flags),
        })
        if flags:
            flagged.append(building_id)

    declared_candidate_count = int(heights.get("candidate_count", len(candidates)))
    if declared_candidate_count != len(candidates):
        raise ValueError("height candidate count drifted from building rows")

    selected_resolution = selection.get("selected_resolution_m")
    terrain_blockers = [str(v) for v in (selection.get("blockers") or [])]
    remaining_gates = [str(v) for v in (selection.get("remaining_runtime_gates") or [])]

    blockers: list[str] = []
    if candidates:
        blockers.append("secondary_independent_height_validation_missing")
    if selected_resolution is None:
        blockers.append("terrain_lod_candidate_missing")
    if terrain_blockers:
        blockers.extend(f"terrain_lod:{value}" for value in terrain_blockers)
    if selected_resolution is not None and remaining_gates:
        blockers.append("terrain_runtime_validation_missing")

    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "manual_frontier_ready": selected_resolution is not None and not terrain_blockers,
        "height_review": {
            "candidate_count": len(candidates),
            "flagged_candidate_count": len(flagged),
            "flagged_building_ids": sorted(flagged),
            "candidates": candidates,
            "independent_secondary_validation_required": bool(candidates),
            "source_candidate_digest": heights.get("candidate_digest"),
        },
        "terrain_review": {
            "selected_resolution_m": float(selected_resolution) if selected_resolution is not None else None,
            "selected_p95_abs_error_m": selection.get("selected_p95_abs_error_m"),
            "remaining_runtime_gates": remaining_gates,
            "source_evidence_digest": terrain.get("evidence_digest"),
        },
        "blockers": sorted(set(blockers)),
        "runtime_promotion_allowed": False,
        "status": "manual_review_ready_runtime_forbidden" if selected_resolution is not None and not terrain_blockers else "manual_review_not_ready",
        "next_actions": {
            "heights": "cross_check_candidates_against_independent_authoritative_height_source" if candidates else "no_height_candidates_to_validate",
            "terrain": "run_seams_normals_collisions_streaming_performance_photo_match_gates" if selected_resolution is not None else "resolve_terrain_lod_candidate",
        },
    }
    result["review_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--height-candidates", type=Path, required=True)
    parser.add_argument("--terrain-lod", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.height_candidates, args.terrain_lod)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CITYGEN_MANUAL_FRONTIER_REVIEW_OK", result["cell_id"], result["manual_frontier_ready"], result["review_digest"])


if __name__ == "__main__":
    main()
