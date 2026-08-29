#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-discovered-road-cell-coverage-frontier-v1"
TARGET_CRS = "EPSG:31370"
CELL_SIZE_M = 500
REQUIRED_CELL_MATURITY_GATES = {
    "collisions",
    "heights",
    "performance",
    "photo_match",
    "runtime_geometry",
    "streaming",
    "terrain",
}


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: invalid JSON {path}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: invalid object {path}")
    return value


def root_from_source(source: Path) -> Path:
    resolved = source.resolve()
    for parent in [resolved.parent, *resolved.parents]:
        if parent.name == "grand-bruxelles-game":
            return parent
    raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: source outside grand-bruxelles-game")


def cell_id(easting: int, northing: int) -> str:
    return f"bxl-e{easting}-n{northing}-s{CELL_SIZE_M}"


def cell_bbox(easting: int, northing: int) -> list[int]:
    return [easting, northing, easting + CELL_SIZE_M, northing + CELL_SIZE_M]


def segment_candidate_cells(p0: list[float], p1: list[float], intersects) -> list[tuple[int, int]]:
    xmin, xmax = sorted((float(p0[0]), float(p1[0])))
    ymin, ymax = sorted((float(p0[1]), float(p1[1])))
    e0 = math.floor(xmin / CELL_SIZE_M) * CELL_SIZE_M
    e1 = math.floor(xmax / CELL_SIZE_M) * CELL_SIZE_M
    n0 = math.floor(ymin / CELL_SIZE_M) * CELL_SIZE_M
    n1 = math.floor(ymax / CELL_SIZE_M) * CELL_SIZE_M
    hits: list[tuple[int, int]] = []
    for east in range(e0, e1 + CELL_SIZE_M, CELL_SIZE_M):
        for north in range(n0, n1 + CELL_SIZE_M, CELL_SIZE_M):
            if intersects(p0, p1, cell_bbox(east, north)):
                hits.append((east, north))
    return hits


def validate_registered_cell_manifest_identity(manifest: dict[str, Any], row: dict[str, Any]) -> None:
    if manifest.get("format") != "grand-bruxelles-cell-maturity-v1":
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest format drift")
    if manifest.get("cell_id") != row.get("cell_id") or manifest.get("crs") != TARGET_CRS:
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest identity drift")
    manifest_bbox = manifest.get("bbox")
    if not isinstance(manifest_bbox, list) or len(manifest_bbox) != 4 or manifest_bbox != row.get("bbox"):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest identity drift")
    maturity = manifest.get("maturity")
    if not isinstance(maturity, dict) or maturity.get("state") != row.get("maturity_state"):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest maturity drift")
    gates = maturity.get("gates")
    if not isinstance(gates, dict):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest gate drift")
    if set(gates) != REQUIRED_CELL_MATURITY_GATES:
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest gate set drift")
    for gate_name, gate_value in gates.items():
        if not isinstance(gate_name, str) or not gate_name or gate_value is not False:
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest gate opened")


def load_registered_cell_ids(cells_path: Path) -> set[str]:
    registered = load_json(cells_path)
    if registered.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell schema drift")
    for key in (
        "collision_authorized",
        "jouable_promotion_authorized",
        "rendered_geometry_authorized",
        "road_crosswalk_authorized",
        "runtime_directory_scan_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
    ):
        if registered.get(key) is not False:
            raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell authorization opened: {key}")

    registered_entries = registered.get("entries")
    if not isinstance(registered_entries, list):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell entries drift")
    registered_id_list: list[str] = []
    project_root = Path(__file__).resolve().parents[1]
    manifest_root = (project_root / "data/cell_manifests").resolve()
    for row in registered_entries:
        if not isinstance(row, dict) or not isinstance(row.get("cell_id"), str) or not row["cell_id"]:
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell identity drift")
        for key in (
            "collision_authorized",
            "jouable_promotion_authorized",
            "rendered_geometry_authorized",
            "runtime_mount_authorized",
            "safe_spawn_authorized",
        ):
            if row.get(key) is not False:
                raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell entry authorization opened: {key}")
        if row.get("evidence_only") is not True:
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell evidence-only drift")
        if row.get("crs") != TARGET_CRS:
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell CRS drift")
        bbox = row.get("bbox")
        if not isinstance(bbox, list) or len(bbox) != 4:
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell bbox drift")
        east, north = int(bbox[0]), int(bbox[1])
        if bbox != cell_bbox(east, north) or row["cell_id"] != cell_id(east, north):
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell bbox identity drift")

        manifest_path = row.get("manifest_path")
        manifest_sha = row.get("manifest_sha256")
        if not isinstance(manifest_path, str) or not manifest_path.startswith("data/cell_manifests/") or Path(manifest_path).is_absolute():
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest path drift")
        if not isinstance(manifest_sha, str) or len(manifest_sha) != 64 or any(ch not in "0123456789abcdef" for ch in manifest_sha):
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest sha drift")
        resolved_manifest = (project_root / manifest_path).resolve()
        try:
            resolved_manifest.relative_to(manifest_root)
        except ValueError as exc:
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest path drift") from exc
        if not resolved_manifest.is_file():
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest missing")
        actual_manifest_sha = hashlib.sha256(resolved_manifest.read_bytes()).hexdigest()
        if actual_manifest_sha != manifest_sha:
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell manifest sha drift")
        validate_registered_cell_manifest_identity(load_json(resolved_manifest), row)

        registered_id_list.append(row["cell_id"])
    registered_ids = set(registered_id_list)
    if len(registered_id_list) != len(registered_ids):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: duplicate registered cell")
    if len(registered_ids) != int(registered.get("registered_cell_count", -1)):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell accounting drift")
    return registered_ids


def _build_unchecked(source_path: Path, frame_path: Path, cells_path: Path) -> dict[str, Any]:
    source_path, frame_path, cells_path = map(Path, (source_path, frame_path, cells_path))
    root = root_from_source(source_path)
    registered_ids = load_registered_cell_ids(cells_path)
    evidence_mod = load_module(root / "tools/build_discovered_road_cell_intersection_evidence.py", "intersection_evidence_for_coverage")
    evidence = evidence_mod.build_evidence(source_path, frame_path, cells_path)
    source = load_json(source_path)

    zero_ids = sorted(int(row["road_osm_id"]) for row in evidence["candidates"] if int(row["intersection_count"]) == 0)
    if len(zero_ids) != int(evidence["zero_intersection_count"]):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: zero-intersection accounting drift")

    roads: dict[int, dict[str, Any]] = {}
    for row in source.get("roads") or []:
        if isinstance(row, dict) and int(row.get("osm_id", 0)) > 0:
            rid = int(row["osm_id"])
            if rid in roads:
                raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: duplicate source road {rid}")
            roads[rid] = row

    east0 = float(evidence["frame_origin_easting_m"])
    north0 = float(evidence["frame_origin_northing_m"])
    cell_roads: dict[tuple[int, int], set[int]] = {}
    for rid in zero_ids:
        road = roads.get(rid)
        if not road:
            raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: missing source road {rid}")
        points = road.get("points") or []
        if len(points) < 2:
            raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: invalid source geometry {rid}")
        lambert = [[east0 + float(point[0]), north0 - float(point[1])] for point in points]
        hits: set[tuple[int, int]] = set()
        for idx in range(len(lambert) - 1):
            hits.update(segment_candidate_cells(lambert[idx], lambert[idx + 1], evidence_mod.segment_intersects_rect))
        if not hits:
            raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: source geometry produced no cells {rid}")
        for key in hits:
            cell_roads.setdefault(key, set()).add(rid)

    candidates = []
    overlap_count = 0
    for east, north in sorted(cell_roads):
        cid = cell_id(east, north)
        is_registered = cid in registered_ids
        overlap_count += int(is_registered)
        candidates.append({
            "cell_id": cid,
            "crs": TARGET_CRS,
            "bbox": cell_bbox(east, north),
            "cell_size_m": CELL_SIZE_M,
            "road_osm_ids": sorted(cell_roads[(east, north)]),
            "road_count": len(cell_roads[(east, north)]),
            "registered": is_registered,
            "manifest_path": None,
            "source_registration_ready": False,
        })

    covered = sorted({rid for row in candidates for rid in row["road_osm_ids"]})
    uncovered = sorted(set(zero_ids) - set(covered))
    payload = {
        "format": FORMAT,
        "crs": TARGET_CRS,
        "cell_size_m": CELL_SIZE_M,
        "source_intersection_evidence_sha256": evidence["evidence_sha256"],
        "source_zero_intersection_road_count": len(zero_ids),
        "source_zero_intersection_road_osm_ids": zero_ids,
        "candidate_cell_count": len(candidates),
        "candidate_cells": candidates,
        "covered_zero_intersection_road_count": len(covered),
        "uncovered_zero_intersection_road_count": len(uncovered),
        "uncovered_zero_intersection_road_osm_ids": uncovered,
        "registered_cell_overlap_count": overlap_count,
        "candidate_manifest_creation_authorized": False,
        "cell_registration_authorized": False,
        "municipality_inference_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_mount_authorized": False,
        "render_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_authorized": False,
    }
    payload["frontier_sha256"] = sha256_json(payload)
    return payload


def validate_structure(frontier: dict[str, Any]) -> None:
    if frontier.get("format") != FORMAT or frontier.get("crs") != TARGET_CRS or int(frontier.get("cell_size_m", -1)) != CELL_SIZE_M:
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: format/CRS/grid drift")
    for key in (
        "candidate_manifest_creation_authorized", "cell_registration_authorized", "municipality_inference_authorized",
        "road_cell_mapping_authorized", "runtime_mount_authorized", "render_authorized", "collision_authorized",
        "safe_spawn_authorized", "jouable_authorized",
    ):
        if frontier.get(key) is not False:
            raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_FAIL: authorization opened: {key}")
    ids = frontier.get("source_zero_intersection_road_osm_ids")
    if not isinstance(ids, list) or any(not isinstance(rid, int) or rid <= 0 for rid in ids) or ids != sorted(set(ids)) or len(ids) != int(frontier.get("source_zero_intersection_road_count", -1)):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: source road identity drift")
    source_id_set = set(ids)
    rows = frontier.get("candidate_cells")
    if not isinstance(rows, list) or len(rows) != int(frontier.get("candidate_cell_count", -1)):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: candidate cell accounting drift")
    cell_ids = [row.get("cell_id") for row in rows]
    if cell_ids != sorted(set(cell_ids)):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: candidate cell identity/order drift")
    for row in rows:
        bbox = row.get("bbox")
        roads = row.get("road_osm_ids")
        if row.get("crs") != TARGET_CRS or int(row.get("cell_size_m", -1)) != CELL_SIZE_M:
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: candidate cell CRS/size drift")
        if not isinstance(bbox, list) or len(bbox) != 4 or cell_id(int(bbox[0]), int(bbox[1])) != row.get("cell_id") or bbox != cell_bbox(int(bbox[0]), int(bbox[1])):
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: candidate cell bbox identity drift")
        if not isinstance(roads, list) or any(not isinstance(rid, int) or rid <= 0 for rid in roads) or roads != sorted(set(roads)) or len(roads) != int(row.get("road_count", -1)):
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: candidate road accounting drift")
        if not set(roads).issubset(source_id_set):
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: candidate road outside zero-intersection set")
        if row.get("registered") is not False or row.get("manifest_path") is not None or row.get("source_registration_ready") is not False:
            raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: candidate registration leaked")
    covered = sorted({rid for row in rows for rid in row["road_osm_ids"]})
    uncovered = sorted(source_id_set - set(covered))
    if len(covered) != int(frontier.get("covered_zero_intersection_road_count", -1)) or uncovered != frontier.get("uncovered_zero_intersection_road_osm_ids") or len(uncovered) != int(frontier.get("uncovered_zero_intersection_road_count", -1)):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: coverage accounting drift")
    if int(frontier.get("registered_cell_overlap_count", -1)) != 0:
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: registered cell overlap")
    unsigned = dict(frontier)
    stored = unsigned.pop("frontier_sha256", None)
    if stored != sha256_json(unsigned):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: frontier sha drift")


def build_frontier(source_path: Path, frame_path: Path, cells_path: Path) -> dict[str, Any]:
    frontier = _build_unchecked(source_path, frame_path, cells_path)
    validate_structure(frontier)
    return frontier


def validate_frontier(frontier: dict[str, Any], source_path: Path, frame_path: Path, cells_path: Path) -> None:
    validate_structure(frontier)
    expected = _build_unchecked(source_path, frame_path, cells_path)
    if canonical_json(frontier) != canonical_json(expected):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_FAIL: source binding drift")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("data/osm/vertical_slice_01.game.json"))
    parser.add_argument("--frame", type=Path, default=Path("data/qa/osm_road_frame_correction_impact.contract.json"))
    parser.add_argument("--cells", type=Path, default=Path("data/provenance/brussels_registered_cell_manifest_index.json"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    frontier = build_frontier(args.source, args.frame, args.cells)
    validate_frontier(frontier, args.source, args.frame, args.cells)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(frontier, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"DISCOVERED_ROAD_CELL_COVERAGE_FRONTIER_GREEN roads={frontier['source_zero_intersection_road_count']} cells={frontier['candidate_cell_count']} sha256={frontier['frontier_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
