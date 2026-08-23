#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

ROAD_AUTH_KEYS = (
    "collision_authorized",
    "jouable_authorized",
    "render_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
)
CELL_AUTH_KEYS = (
    "runtime_directory_scan_authorized",
    "road_crosswalk_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)
ROW_AUTH_KEYS = (
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)


def _load(path: Path):
    if not path.is_file():
        raise RuntimeError(f"required evidence file missing: {path}")
    try:
        return json.loads(path.read_text())
    except Exception as exc:
        raise RuntimeError(f"invalid JSON: {path}") from exc


def _require_false(doc, keys, label):
    for key in keys:
        if doc.get(key) is not False:
            raise RuntimeError(f"{label} authorization must remain false: {key}")


def _require_all_authorizations_false(doc, label):
    if not isinstance(doc, dict):
        raise RuntimeError(f"{label} must be an object")
    for key, value in doc.items():
        if key.endswith("_authorized") and value is not False:
            raise RuntimeError(f"{label} authorization must remain false: {key}")


def validate_handshake(road_index_path: Path, cell_index_path: Path, crosswalk_path: Path):
    road = _load(Path(road_index_path))
    cells = _load(Path(cell_index_path))
    crosswalk = _load(Path(crosswalk_path))

    if road.get("format") != "grand-bruxelles-road-runtime-index-v1":
        raise RuntimeError("unsupported road index format")
    if road.get("source_lookup_only") is not True:
        raise RuntimeError("road index must remain source_lookup_only")
    road_auth = road.get("authorization") or {}
    if road_auth.get("source_lookup_only") is not True:
        raise RuntimeError("road index authorization must remain source_lookup_only")
    _require_false(road_auth, ROAD_AUTH_KEYS, "road index")
    _require_all_authorizations_false(road_auth, "road index")

    road_ids = set()
    for document in road.get("documents") or []:
        if not isinstance(document.get("sha256"), str) or len(document["sha256"]) != 64:
            raise RuntimeError("road source document SHA-256 missing or malformed")
        for road_id in document.get("road_ids") or []:
            if not isinstance(road_id, int) or road_id <= 0:
                raise RuntimeError("invalid road id in source index")
            if road_id in road_ids:
                raise RuntimeError(f"duplicate road id in source index: {road_id}")
            road_ids.add(road_id)
    if not road_ids:
        raise RuntimeError("road source index is empty")

    if cells.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise RuntimeError("unsupported registered-cell index schema")
    if cells.get("destination_readiness") != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise RuntimeError("registered-cell index readiness widened")
    _require_false(cells, CELL_AUTH_KEYS, "registered-cell index")
    _require_all_authorizations_false(cells, "registered-cell index")
    cell_ids = set()
    for entry in cells.get("entries") or []:
        cell_id = entry.get("cell_id")
        if not isinstance(cell_id, str) or not cell_id:
            raise RuntimeError("invalid registered cell id")
        if cell_id in cell_ids:
            raise RuntimeError(f"duplicate registered cell id: {cell_id}")
        if entry.get("evidence_only") is not True:
            raise RuntimeError(f"registered cell is not evidence-only: {cell_id}")
        _require_false(entry, ROW_AUTH_KEYS, f"registered cell {cell_id}")
        _require_all_authorizations_false(entry, f"registered cell {cell_id}")
        cell_ids.add(cell_id)
    if len(cell_ids) != cells.get("registered_cell_count"):
        raise RuntimeError("registered-cell count mismatch")

    if crosswalk.get("schema") != "grand-bruxelles-road-registered-cell-crosswalk-v1":
        raise RuntimeError("unsupported road-cell crosswalk schema")
    if crosswalk.get("destination_readiness") != "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY":
        raise RuntimeError("road-cell readiness widened")
    _require_false(crosswalk, (
        "runtime_directory_scan_authorized",
        "runtime_mount_authorized",
        "rendered_geometry_authorized",
        "collision_authorized",
        "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ), "road-cell crosswalk")
    _require_all_authorizations_false(crosswalk, "road-cell crosswalk")

    seen_roads = set()
    mapped_cells = set()
    rows = crosswalk.get("rows") or []
    if not rows:
        raise RuntimeError("road-cell crosswalk has no explicit rows")
    for row in rows:
        road_id = row.get("road_osm_id")
        cell_id = row.get("cell_id")
        if road_id not in road_ids:
            raise RuntimeError(f"road is not in deterministic source index: {road_id}")
        if cell_id not in cell_ids:
            raise RuntimeError(f"cell is not in deterministic registered index: {cell_id}")
        if road_id in seen_roads:
            raise RuntimeError(f"road maps to more than one row: {road_id}")
        if row.get("mapping_evidence_only") is not True:
            raise RuntimeError(f"road-cell mapping is not evidence-only: {road_id}")
        _require_false(row, ROW_AUTH_KEYS, f"road-cell row {road_id}")
        _require_all_authorizations_false(row, f"road-cell row {road_id}")
        seen_roads.add(road_id)
        mapped_cells.add(cell_id)

    return {
        "mapped_road_count": len(seen_roads),
        "mapped_cell_count": len(mapped_cells),
        "runtime_authorized": False,
        "destination_readiness": "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--road-index", required=True)
    parser.add_argument("--cell-index", required=True)
    parser.add_argument("--crosswalk", required=True)
    args = parser.parse_args()
    result = validate_handshake(Path(args.road_index), Path(args.cell_index), Path(args.crosswalk))
    print(
        "ROAD_REGISTERED_CELL_HANDSHAKE_OK "
        f"roads={result['mapped_road_count']} cells={result['mapped_cell_count']} "
        "runtime_authorized=false"
    )


if __name__ == "__main__":
    main()
