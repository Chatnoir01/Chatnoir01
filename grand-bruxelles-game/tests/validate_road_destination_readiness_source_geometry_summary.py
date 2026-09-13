#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path, PurePosixPath
from typing import Any


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key: {key}")
        out[key] = value
    return out


def _finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite JSON number: {value}")
    return parsed


def _load(path: Path) -> Any:
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=_strict_object,
        parse_float=_finite_float,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"non-finite JSON number: {value}")),
    )


def _repo_file(root: Path, value: Any, label: str) -> Path:
    if not isinstance(value, str) or not value or value != value.strip() or "\\" in value:
        raise ValueError(f"{label} must be a canonical repository-relative POSIX path")
    pure = PurePosixPath(value)
    if pure.is_absolute() or any(part in {".", ".."} for part in pure.parts) or str(pure) != value:
        raise ValueError(f"{label} must be a canonical repository-relative POSIX path")
    root_resolved = root.resolve()
    candidate = (root_resolved / value).resolve()
    try:
        candidate.relative_to(root_resolved)
    except ValueError as exc:
        raise ValueError(f"{label} escapes repository root") from exc
    if not candidate.is_file():
        raise ValueError(f"{label} does not exist: {value}")
    return candidate


def _roads_by_id(source: Any, label: str) -> dict[int, dict[str, Any]]:
    if not isinstance(source, dict) or not isinstance(source.get("roads"), list):
        raise ValueError(f"{label} must contain roads array")
    out: dict[int, dict[str, Any]] = {}
    for index, road in enumerate(source["roads"]):
        if not isinstance(road, dict):
            raise ValueError(f"{label}.roads[{index}] must be an object")
        osm_id = road.get("osm_id")
        if isinstance(osm_id, bool) or not isinstance(osm_id, int) or osm_id <= 0:
            raise ValueError(f"{label}.roads[{index}].osm_id must be a positive integer")
        if osm_id in out:
            raise ValueError(f"duplicate source road osm_id={osm_id}")
        out[osm_id] = road
    return out


def _summary(points: Any, label: str) -> tuple[int, list[float]]:
    if not isinstance(points, list) or not points:
        raise ValueError(f"{label} must be a non-empty array")
    xs: list[float] = []
    zs: list[float] = []
    for index, point in enumerate(points):
        if not isinstance(point, list) or len(point) != 2:
            raise ValueError(f"{label}[{index}] must be a 2D point")
        coords: list[float] = []
        for axis, value in enumerate(point):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
                raise ValueError(f"{label}[{index}][{axis}] must be finite numeric")
            coords.append(float(value))
        xs.append(coords[0])
        zs.append(coords[1])
    return len(points), [min(xs), min(zs), max(xs), max(zs)]


def validate(catalog: Any, *, root: Path) -> int:
    if not isinstance(catalog, dict) or catalog.get("schema") != "grand-bruxelles-road-destination-readiness-catalog-v1":
        raise ValueError("unexpected catalog schema")
    rows = catalog.get("destinations")
    if not isinstance(rows, list) or not rows:
        raise ValueError("catalog destinations missing")

    source_cache: dict[str, dict[int, dict[str, Any]]] = {}
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ValueError(f"destination row {index} must be an object")
        source_path = row.get("source_path")
        source_file = _repo_file(root, source_path, f"destination row {index}.source_path")
        if source_path not in source_cache:
            source_cache[source_path] = _roads_by_id(_load(source_file), str(source_path))

        road_osm_id = row.get("road_osm_id")
        if isinstance(road_osm_id, bool) or not isinstance(road_osm_id, int) or road_osm_id <= 0:
            raise ValueError(f"destination row {index}.road_osm_id must be a positive integer")
        road = source_cache[source_path].get(road_osm_id)
        if road is None:
            raise ValueError(f"destination row {index}.road_osm_id={road_osm_id} missing from source")

        expected_count, expected_bbox = _summary(road.get("points"), f"source road osm_id={road_osm_id}.points")
        declared_count = row.get("source_local_point_count")
        if isinstance(declared_count, bool) or not isinstance(declared_count, int) or declared_count != expected_count:
            raise ValueError(f"destination row {index}.source_local_point_count does not match source points")

        bbox = row.get("source_local_bbox")
        if not isinstance(bbox, list) or len(bbox) != 4:
            raise ValueError(f"destination row {index}.source_local_bbox must contain four coordinates")
        normalized: list[float] = []
        for axis, value in enumerate(bbox):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
                raise ValueError(f"destination row {index}.source_local_bbox[{axis}] must be finite numeric")
            normalized.append(float(value))
        if normalized != expected_bbox:
            raise ValueError(f"destination row {index}.source_local_bbox does not match source points")
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalog", type=Path)
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    count = validate(_load(args.catalog), root=args.root)
    print(
        "ROAD_DESTINATION_READINESS_SOURCE_GEOMETRY_SUMMARY_OK "
        f"destinations={count} source_local_point_count_bound=true source_local_bbox_bound=true "
        "finite_source_geometry_summary_required=true source_geometry_summary_fail_closed=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
