#!/usr/bin/env python3
"""Build deterministic geometry lookup metadata for locked OSM road destinations.

This index is provenance/lookup metadata only. It grants no render, collision,
runtime-mount, safe-spawn, or JOUABLE authorization.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
from typing import Any, NoReturn

FORMAT = "grand-bruxelles-road-source-geometry-index-v1"
TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent
CATALOG_SCRIPT = TOOLS_DIR / "build_road_destination_catalog.py"

_spec = importlib.util.spec_from_file_location("road_destination_catalog", CATALOG_SCRIPT)
if _spec is None or _spec.loader is None:
    raise RuntimeError(f"cannot load road destination catalog: {CATALOG_SCRIPT}")
_catalog = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_catalog)

AUTHORIZATION = {
    "source_lookup_only": True,
    "render_authorized": False,
    "collision_authorized": False,
    "runtime_mount_authorized": False,
    "safe_spawn_authorized": False,
    "jouable_authorized": False,
}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ROAD_SOURCE_GEOMETRY_INDEX_FAIL: {message}")


def finite_number(value: Any, label: str) -> float:
    if type(value) not in (int, float):
        fail(f"{label} is not a JSON number")
    number = float(value)
    if not math.isfinite(number):
        fail(f"{label} is not finite")
    return number


def canonical_points(raw: Any, label: str) -> list[list[float]]:
    if type(raw) is not list or len(raw) < 2:
        fail(f"{label} must contain at least two points")
    points: list[list[float]] = []
    for index, pair in enumerate(raw):
        if type(pair) is not list or len(pair) != 2:
            fail(f"{label}[{index}] must be a 2D point")
        points.append([
            finite_number(pair[0], f"{label}[{index}][0]"),
            finite_number(pair[1], f"{label}[{index}][1]"),
        ])
    return points


def geometry_sha256(points: list[list[float]]) -> str:
    encoded = json.dumps(points, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def centerline_length_m(points: list[list[float]]) -> float:
    length = 0.0
    for index, (start, end) in enumerate(zip(points, points[1:])):
        segment_length = math.hypot(end[0] - start[0], end[1] - start[1])
        if segment_length == 0.0:
            fail(f"road centerline contains zero-length segment index={index}")
        length += segment_length
    if not math.isfinite(length) or length <= 0.0:
        fail("road centerline has no positive finite source length")
    return length


def serialize_index(payload: dict[str, Any]) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def build_index(source_root: Path) -> dict[str, Any]:
    source_root = source_root.resolve()
    catalog = _catalog.build_catalog(source_root)
    _catalog.validate_contract(catalog)
    catalog_entries = catalog["entries"]
    source_digests = catalog["source_document_sha256"]
    locked_documents = _catalog._locked_documents(source_root)
    repo_root = source_root.parent.parent

    observed: dict[int, dict[str, Any]] = {}
    for document_path in locked_documents:
        relative = document_path.relative_to(repo_root).as_posix()
        raw_bytes = document_path.read_bytes()
        actual_digest = hashlib.sha256(raw_bytes).hexdigest()
        if source_digests.get(relative) != actual_digest:
            fail(f"source digest drift {relative}")
        try:
            raw_text = raw_bytes.decode("utf-8")
        except UnicodeDecodeError as exc:
            fail(f"invalid UTF-8 {relative}: {exc}")
        try:
            document = json.loads(raw_text)
        except json.JSONDecodeError as exc:
            fail(f"invalid JSON {relative}: {exc}")
        if type(document) is not dict or document.get("format") != _catalog.SOURCE_FORMAT:
            fail(f"locked document format drift {relative}")
        roads = document.get("roads")
        if type(roads) is not list:
            fail(f"roads container drift {relative}")
        for index, road in enumerate(roads):
            if type(road) is not dict:
                fail(f"road record drift {relative}#{index}")
            osm_id = road.get("osm_id")
            if type(osm_id) is not int or str(osm_id) not in catalog_entries:
                continue
            if osm_id in observed:
                fail(f"eligible road has multiple runtime source documents osm_id={osm_id}")
            points = canonical_points(road.get("points"), f"{relative} road {osm_id} points")
            expected = catalog_entries[str(osm_id)]
            digest = geometry_sha256(points)
            if digest != expected.get("geometry_sha256") or len(points) != expected.get("point_count"):
                fail(f"catalog geometry binding drift osm_id={osm_id}")
            source_identity = {
                "name": road.get("name"),
                "class": road.get("class"),
                "width": finite_number(road.get("width"), f"{relative} road {osm_id} width"),
                "drivable": road.get("drivable"),
            }
            expected_identity = {
                "name": expected.get("name"),
                "class": expected.get("class"),
                "width": expected.get("width"),
                "drivable": expected.get("drivable"),
            }
            if source_identity != expected_identity or source_identity["drivable"] is not True:
                fail(f"catalog road identity binding drift osm_id={osm_id}")
            xs = [point[0] for point in points]
            zs = [point[1] for point in points]
            observed[osm_id] = {
                "osm_id": osm_id,
                **source_identity,
                "source_path": relative,
                "source_sha256": actual_digest,
                "geometry_sha256": digest,
                "point_count": len(points),
                "centerline_length_m": centerline_length_m(points),
                "bbox": [min(xs), min(zs), max(xs), max(zs)],
            }

    expected_ids = {int(key) for key in catalog_entries}
    if set(observed) != expected_ids:
        missing = sorted(expected_ids - set(observed))
        extra = sorted(set(observed) - expected_ids)
        fail(f"catalog/source identity mismatch missing={missing} extra={extra}")

    return {
        "format": FORMAT,
        "catalog_sha256": catalog["catalog_sha256"],
        "entry_count": len(observed),
        "entries": {str(osm_id): observed[osm_id] for osm_id in sorted(observed)},
        "authorization": dict(AUTHORIZATION),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=PROJECT_DIR / "data" / "osm")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    payload = build_index(args.source_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(serialize_index(payload))
    print(f"ROAD_SOURCE_GEOMETRY_INDEX_OK: entries={payload['entry_count']} catalog_sha256={payload['catalog_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
