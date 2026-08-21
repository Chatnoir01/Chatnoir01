#!/usr/bin/env python3
"""Build a fail-closed terrain/runtime candidate manifest for one CityGen cell.

This stage combines two already-produced evidence contracts:
- source-faithful DTM LOD evidence; and
- independent secondary validation of measured building-height candidates.

It does not materialize a mesh, authorize terrain runtime, collisions, navigation,
streaming, or production discovery. Only individually secondary-validated building
heights are carried forward; blocked heights are never guessed or substituted.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-citygen-terrain-runtime-candidate-manifest-v1"
TERRAIN_LOD_FORMAT = "grand-bruxelles-cell-dtm-lod-evidence-v1"
SECONDARY_FORMAT = "grand-bruxelles-citygen-secondary-height-validation-v1"
CRS = "EPSG:31370"
REMAINING_RUNTIME_GATES = [
    "height_contract",
    "terrain_mesh",
    "seams",
    "normals",
    "collisions",
    "navigation",
    "streaming",
    "performance",
    "photo_match",
]


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _finite_positive(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) and out > 0.0 else None


def _require_digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value.casefold()):
        raise ValueError(f"{label} must be a sha256 hex digest")
    return value.casefold()


def _verified_embedded_digest(payload: dict[str, Any], field: str, label: str) -> str:
    expected = _require_digest(payload.get(field), label)
    unsigned = {key: value for key, value in payload.items() if key != field}
    actual = _digest(unsigned)
    if actual != expected:
        raise ValueError(f"{label} does not match payload content")
    return expected


def build(terrain_lod_path: Path, secondary_validation_path: Path) -> dict[str, Any]:
    terrain = _read(terrain_lod_path)
    secondary = _read(secondary_validation_path)

    if terrain.get("format") != TERRAIN_LOD_FORMAT or terrain.get("crs") != CRS:
        raise ValueError("unsupported terrain LOD evidence")
    if secondary.get("format") != SECONDARY_FORMAT or secondary.get("crs") != CRS:
        raise ValueError("unsupported secondary height validation")

    cell_id = terrain.get("cell_id")
    if not isinstance(cell_id, str) or not cell_id or secondary.get("cell_id") != cell_id:
        raise ValueError("terrain/height candidate cell identity mismatch")

    if terrain.get("runtime_approved") is not False:
        raise ValueError("terrain LOD evidence must remain runtime-unapproved")
    selection = terrain.get("selection") or {}
    if not isinstance(selection, dict) or selection.get("runtime_approved") is not False:
        raise ValueError("terrain LOD selection must remain runtime-unapproved")
    selected_resolution = _finite_positive(selection.get("selected_resolution_m"))
    if selected_resolution is None:
        raise ValueError("terrain LOD has no selected source-faithful resolution")
    if selection.get("blockers"):
        raise ValueError("terrain LOD selection still carries blockers")

    if secondary.get("runtime_promotion_allowed") is not False or int(secondary.get("runtime_approved_count", -1)) != 0:
        raise ValueError("secondary height validation must forbid runtime promotion")

    candidate_count = int(secondary.get("candidate_count", -1))
    validated_count = int(secondary.get("validated_candidate_count", -1))
    blocked_count = int(secondary.get("blocked_candidate_count", -1))
    rows = secondary.get("candidates")
    if not isinstance(rows, list) or candidate_count < 0 or validated_count < 0 or blocked_count < 0:
        raise ValueError("secondary height validation counts are invalid")
    if candidate_count != len(rows) or validated_count + blocked_count != candidate_count:
        raise ValueError("secondary height validation counts drifted")

    validated_heights: list[dict[str, Any]] = []
    observed_validated = 0
    observed_blocked = 0
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("secondary height candidate row is invalid")
        building_id = str(row.get("building_id") or "")
        height = _finite_positive(row.get("candidate_height_m"))
        if not building_id or height is None:
            raise ValueError("secondary height candidate is missing identity or positive height")
        if row.get("runtime_approved") is not False:
            raise ValueError(f"secondary height row unexpectedly carries runtime approval: {building_id}")
        status = str(row.get("secondary_status") or "")
        if status == "validated":
            observed_validated += 1
            validated_heights.append(
                {
                    "building_id": building_id,
                    "height_m": height,
                    "source": "secondary_validated_measured_dsm_dtm_candidate",
                    "semantic_height_m": row.get("semantic_height_m"),
                    "abs_delta_m": row.get("abs_delta_m"),
                    "semantic_match_score": row.get("semantic_match_score"),
                    "semantic_match_margin": row.get("semantic_match_margin"),
                    "runtime_approved": False,
                }
            )
        else:
            observed_blocked += 1

    if observed_validated != validated_count or observed_blocked != blocked_count:
        raise ValueError("secondary height status counts drifted")

    terrain_digest = _verified_embedded_digest(terrain, "evidence_digest", "terrain evidence digest")
    secondary_digest = _verified_embedded_digest(secondary, "validation_digest", "secondary validation digest")
    height_contract_complete = bool(secondary.get("secondary_validation_complete")) and blocked_count == 0 and candidate_count > 0

    blockers = [
        "terrain_mesh_not_materialized",
        "terrain_seams_not_validated",
        "terrain_normals_not_validated",
        "terrain_collisions_not_validated",
        "navigation_not_validated",
        "streaming_not_validated",
        "performance_not_validated",
        "photo_match_not_validated",
    ]
    if not height_contract_complete:
        blockers.insert(0, "secondary_height_contract_incomplete")

    remaining_gates = [gate for gate in REMAINING_RUNTIME_GATES if gate != "height_contract" or not height_contract_complete]
    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bbox": terrain.get("bbox"),
        "terrain": {
            "source": terrain.get("source"),
            "selected_resolution_m": selected_resolution,
            "selected_p95_abs_error_m": selection.get("selected_p95_abs_error_m"),
            "selected_vertex_count": selection.get("selected_vertex_count"),
            "source_pixel_size_m": terrain.get("source_pixel_size_m"),
            "terrain_lod_evidence_digest": terrain_digest,
            "source_raster_validation_digest": terrain.get("source_raster_validation_digest"),
            "source_value_evidence_digest": terrain.get("source_value_evidence_digest"),
            "mesh_materialized": False,
            "runtime_approved": False,
        },
        "building_heights": {
            "mode": "secondary_validated_subset_only_no_fallback",
            "source_validation_digest": secondary_digest,
            "candidate_count": candidate_count,
            "validated_count": validated_count,
            "blocked_count": blocked_count,
            "contract_complete": height_contract_complete,
            "validated": sorted(validated_heights, key=lambda row: row["building_id"]),
            "unvalidated_fallback_allowed": False,
            "runtime_approved": False,
        },
        "blockers": blockers,
        "remaining_runtime_gates": remaining_gates,
        "status": (
            "terrain_candidate_manifest_pending_mesh_and_runtime_gates"
            if height_contract_complete
            else "terrain_candidate_manifest_height_contract_incomplete"
        ),
        "terrain_runtime_authorized": False,
        "runtime_geometry_authorized": False,
        "collision_authorized": False,
        "navigation_authorized": False,
        "runtime_mount_authorized": False,
        "production_discovery_eligible": False,
        "automatic_production_mutation": False,
        "next_action": (
            "materialize_source_faithful_terrain_mesh_then_validate_seams_normals"
            if height_contract_complete
            else "resolve_blocked_secondary_heights_without_guessing_while_materializing_terrain_mesh_candidate"
        ),
    }
    result["candidate_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terrain-lod", type=Path, required=True)
    parser.add_argument("--secondary-validation", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.terrain_lod, args.secondary_validation)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "TERRAIN_RUNTIME_CANDIDATE_OK",
        result["cell_id"],
        f"resolution={result['terrain']['selected_resolution_m']}",
        f"validated_heights={result['building_heights']['validated_count']}",
        f"blocked_heights={result['building_heights']['blocked_count']}",
        "runtime_mount=false",
        "collision=false",
    )


if __name__ == "__main__":
    main()
