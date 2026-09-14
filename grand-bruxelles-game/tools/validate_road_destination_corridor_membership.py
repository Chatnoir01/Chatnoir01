#!/usr/bin/env python3
"""Validate shipped road selection against the historical corridor-ribbon predicate."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

SOURCE_FORMAT = "grand-bruxelles-osm-v1"
SOURCE_ATTRIBUTION = "OpenStreetMap contributors via Overpass API"
SOURCE_LICENSE = "ODbL-1.0"
EXPECTED_ANCHOR_IDS = ("midi", "anneessens", "bourse", "grand_place")


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ROAD_DESTINATION_CORRIDOR_MEMBERSHIP_FAIL: {message}")


def finite_number(value: Any, label: str) -> float:
    if type(value) not in (int, float) or not math.isfinite(float(value)):
        fail(f"{label} must be a finite number")
    return float(value)


def point_segment_distance(
    point: tuple[float, float],
    start: tuple[float, float],
    end: tuple[float, float],
) -> float:
    px, pz = point
    ax, az = start
    bx, bz = end
    dx = bx - ax
    dz = bz - az
    denom = dx * dx + dz * dz
    if denom == 0.0:
        return math.hypot(px - ax, pz - az)
    t = ((px - ax) * dx + (pz - az) * dz) / denom
    t = max(0.0, min(1.0, t))
    nearest_x = ax + t * dx
    nearest_z = az + t * dz
    return math.hypot(px - nearest_x, pz - nearest_z)


def point_polyline_distance(
    point: tuple[float, float],
    anchors: list[tuple[float, float]],
) -> float:
    return min(
        point_segment_distance(point, anchors[index], anchors[index + 1])
        for index in range(len(anchors) - 1)
    )


def min_feature_distance(
    points: list[tuple[float, float]],
    anchors: list[tuple[float, float]],
) -> float:
    # Must remain generation-equivalent to tools/make_runtime_slice.py:
    # the minimum of ROAD VERTEX distances to ordered corridor polyline segments.
    return min(point_polyline_distance(point, anchors) for point in points)


def validate_source_payload(payload: Any) -> tuple[int, float]:
    if type(payload) is not dict:
        fail("source root must be an object")
    if payload.get("format") != SOURCE_FORMAT:
        fail("source format drift")
    if payload.get("source") != SOURCE_ATTRIBUTION:
        fail("source attribution drift")
    if payload.get("license") != SOURCE_LICENSE:
        fail("source license drift")

    corridor = payload.get("corridor")
    if type(corridor) is not dict:
        fail("corridor must be an object")
    raw_anchors = corridor.get("anchors")
    if type(raw_anchors) is not list or len(raw_anchors) != len(EXPECTED_ANCHOR_IDS):
        fail("corridor anchors must contain the exact ordered corridor")

    anchors: list[tuple[float, float]] = []
    observed_ids: list[str] = []
    for index, raw_anchor in enumerate(raw_anchors):
        if type(raw_anchor) is not dict:
            fail(f"corridor anchors[{index}] must be an object")
        anchor_id = raw_anchor.get("id")
        if type(anchor_id) is not str:
            fail(f"corridor anchors[{index}].id must be a string")
        observed_ids.append(anchor_id)
        anchors.append(
            (
                finite_number(raw_anchor.get("x"), f"corridor anchors[{index}].x"),
                finite_number(raw_anchor.get("z"), f"corridor anchors[{index}].z"),
            )
        )
    if tuple(observed_ids) != EXPECTED_ANCHOR_IDS:
        fail(f"corridor anchor order drift {observed_ids!r}")

    selection_radius = corridor.get("selection_radius_m")
    if type(selection_radius) is not dict:
        fail("corridor selection_radius_m must be an object")
    road_radius = finite_number(selection_radius.get("roads"), "corridor selection radius roads")
    if road_radius <= 0.0:
        fail("corridor selection radius roads must be positive")

    roads = payload.get("roads")
    if type(roads) is not list:
        fail("roads must be an array")
    for road_index, road in enumerate(roads):
        if type(road) is not dict:
            fail(f"roads[{road_index}] must be an object")
        raw_points = road.get("points")
        if type(raw_points) is not list or len(raw_points) < 2:
            fail(f"roads[{road_index}].points must contain at least two vertices")
        points: list[tuple[float, float]] = []
        for point_index, raw_point in enumerate(raw_points):
            if type(raw_point) is not list or len(raw_point) != 2:
                fail(f"roads[{road_index}].points[{point_index}] must be a [x,z] pair")
            points.append(
                (
                    finite_number(raw_point[0], f"roads[{road_index}].points[{point_index}][0]"),
                    finite_number(raw_point[1], f"roads[{road_index}].points[{point_index}][1]"),
                )
            )
        distance = min_feature_distance(points, anchors)
        if distance > road_radius:
            osm_id = road.get("osm_id")
            fail(
                f"roads[{road_index}] osm_id={osm_id!r} lies outside corridor selection radius: "
                f"distance_m={distance:.6f} radius_m={road_radius:.6f}"
            )
    return len(roads), road_radius


def validate(path: Path) -> tuple[int, float]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"invalid source JSON {path}: {exc}")
    return validate_source_payload(payload)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "data" / "osm" / "vertical_slice_01.game.json",
    )
    args = parser.parse_args()
    road_count, radius = validate(args.source)
    print(
        "ROAD_DESTINATION_CORRIDOR_MEMBERSHIP_OK "
        f"roads={road_count} radius_m={radius:g} "
        "historical_vertex_to_polyline_metric=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
