#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
AUTH_SUFFIX = "_authorized"


def _load(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise RuntimeError(f"required evidence missing: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(f"invalid JSON: {path}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"evidence must be an object: {path}")
    return value


def _require_sha(value: Any, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise RuntimeError(f"{label} SHA-256 missing or malformed")
    return value


def _require_authorizations_closed(value: Any, label: str) -> None:
    if not isinstance(value, dict):
        raise RuntimeError(f"{label} must be an object")
    for key, item in value.items():
        if key.endswith(AUTH_SUFFIX) and item is not False:
            raise RuntimeError(f"{label} authorization must remain false: {key}")


def _bbox_key(value: Any) -> tuple[float, float, float, float]:
    if not isinstance(value, list) or len(value) != 4:
        raise RuntimeError("cell bbox must contain four values")
    result = tuple(float(v) for v in value)
    if result[2] - result[0] != 500.0 or result[3] - result[1] != 500.0:
        raise RuntimeError(f"registered/candidate cell bbox is not exact 500m grid: {result}")
    return result


def _runtime_road_ids(road_index: dict[str, Any]) -> set[int]:
    if road_index.get("format") != "grand-bruxelles-road-runtime-index-v1":
        raise RuntimeError("unsupported road runtime index format")
    if road_index.get("source_lookup_only") is not True:
        raise RuntimeError("road runtime index must remain source_lookup_only")
    auth = road_index.get("authorization") or {}
    if auth.get("source_lookup_only") is not True:
        raise RuntimeError("road runtime index authorization widened")
    _require_authorizations_closed(auth, "road runtime index")
    ids: set[int] = set()
    for document in road_index.get("documents") or []:
        _require_sha(document.get("sha256"), "road document")
        for road_id in document.get("road_ids") or []:
            if not isinstance(road_id, int) or road_id <= 0 or road_id in ids:
                raise RuntimeError(f"invalid/duplicate runtime road id: {road_id}")
            ids.add(road_id)
    if not ids:
        raise RuntimeError("road runtime index is empty")
    return ids


def build_crosswalk(coverage_path: Path, cells_path: Path, road_index_path: Path) -> dict[str, Any]:
    coverage = _load(Path(coverage_path))
    cells = _load(Path(cells_path))
    road_index = _load(Path(road_index_path))

    if coverage.get("schema") != "grand-bruxelles-road-cell-coverage-candidates-v2":
        raise RuntimeError("unsupported road coverage schema")
    if coverage.get("status") != "DISCOVERED_SOURCE_ONLY":
        raise RuntimeError("road coverage readiness widened")
    _require_sha(coverage.get("road_semantic_sha256"), "road semantic")
    _require_sha(coverage.get("semantic_sha256"), "road coverage semantic")
    _require_authorizations_closed(coverage, "road coverage")

    if cells.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise RuntimeError("unsupported registered-cell index schema")
    if cells.get("destination_readiness") != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise RuntimeError("registered-cell readiness widened")
    _require_sha(cells.get("semantic_sha256"), "registered-cell index semantic")
    _require_authorizations_closed(cells, "registered-cell index")

    runtime_ids = _runtime_road_ids(road_index)
    road_cells: dict[int, set[tuple[float, float, float, float]]] = defaultdict(set)
    cell_grid_ids: dict[tuple[float, float, float, float], str] = {}
    for candidate in coverage.get("candidates") or []:
        if not isinstance(candidate, dict):
            raise RuntimeError("road coverage candidate must be an object")
        _require_authorizations_closed(candidate, "road coverage candidate")
        bbox = _bbox_key(candidate.get("bbox"))
        grid_id = candidate.get("grid_cell_id")
        if not isinstance(grid_id, str) or not grid_id:
            raise RuntimeError("road coverage grid id missing")
        if bbox in cell_grid_ids and cell_grid_ids[bbox] != grid_id:
            raise RuntimeError("road coverage bbox maps to multiple grid ids")
        cell_grid_ids[bbox] = grid_id
        for road_id in candidate.get("road_ids") or []:
            if not isinstance(road_id, int) or road_id <= 0:
                raise RuntimeError(f"invalid road id in coverage: {road_id}")
            road_cells[road_id].add(bbox)

    registered_by_bbox: dict[tuple[float, float, float, float], str] = {}
    for entry in cells.get("entries") or []:
        if not isinstance(entry, dict) or entry.get("evidence_only") is not True:
            raise RuntimeError("registered cell must remain evidence-only")
        _require_authorizations_closed(entry, "registered cell")
        bbox = _bbox_key(entry.get("bbox"))
        cell_id = entry.get("cell_id")
        if not isinstance(cell_id, str) or not cell_id:
            raise RuntimeError("registered cell id missing")
        if bbox in registered_by_bbox:
            raise RuntimeError(f"duplicate registered bbox: {bbox}")
        registered_by_bbox[bbox] = cell_id
    if len(registered_by_bbox) != cells.get("registered_cell_count"):
        raise RuntimeError("registered-cell count mismatch")

    rows: list[dict[str, Any]] = []
    excluded_multicell: list[int] = []
    mapped_cells: set[str] = set()
    for road_id in sorted(road_cells):
        all_cells = sorted(road_cells[road_id])
        registered_hits = [bbox for bbox in all_cells if bbox in registered_by_bbox]
        if not registered_hits:
            continue
        if road_id not in runtime_ids:
            raise RuntimeError(f"registered-cell candidate road missing from runtime source index: {road_id}")
        if len(all_cells) != 1:
            excluded_multicell.append(road_id)
            continue
        bbox = all_cells[0]
        cell_id = registered_by_bbox[bbox]
        mapped_cells.add(cell_id)
        rows.append({
            "road_osm_id": road_id,
            "cell_id": cell_id,
            "grid_cell_id": cell_grid_ids[bbox],
            "mapping_basis": "unique_source_coverage_cell_and_registered_bbox",
            "mapping_evidence_only": True,
            "road_cell_mapping_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        })

    unmatched_registered = sorted(set(registered_by_bbox.values()) - mapped_cells)
    result = {
        "schema": "grand-bruxelles-road-registered-cell-crosswalk-v1",
        "destination_readiness": "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY",
        "mapping_policy": "unique_source_coverage_cell_only",
        "coverage_semantic_sha256": coverage["semantic_sha256"],
        "road_semantic_sha256": coverage["road_semantic_sha256"],
        "registered_cell_index_semantic_sha256": cells["semantic_sha256"],
        "mapped_road_count": len(rows),
        "mapped_cell_count": len(mapped_cells),
        "excluded_multicell_road_ids": excluded_multicell,
        "unmatched_registered_cell_ids": unmatched_registered,
        "rows": rows,
        "road_cell_mapping_authorized": False,
        "runtime_directory_scan_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    semantic_basis = dict(result)
    semantic_basis.pop("semantic_sha256", None)
    result["semantic_sha256"] = hashlib.sha256(
        json.dumps(semantic_basis, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--coverage", type=Path, required=True)
    parser.add_argument("--cells", type=Path, required=True)
    parser.add_argument("--road-index", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = build_crosswalk(args.coverage, args.cells, args.road_index)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        print(f"ROAD_REGISTERED_CELL_CROSSWALK_RED: {exc}")
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        "ROAD_REGISTERED_CELL_CROSSWALK_OK "
        f"roads={result['mapped_road_count']} cells={result['mapped_cell_count']} "
        f"excluded_multicell={len(result['excluded_multicell_road_ids'])} "
        f"semantic_sha256={result['semantic_sha256']} runtime_authorized=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
