#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

GAME_ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = GAME_ROOT / "data/osm/vertical_slice_01.game.json"
BUILDER_PATH = GAME_ROOT / "game/scripts/osm_city_builder.gd"
RESOLVER_PATH = GAME_ROOT / "game/scripts/automatic_road_direct_spawn.gd"
LEMONNIER_ID = 359177328
EXPECTED_SOURCE = "OpenStreetMap contributors via Overpass API"
EXPECTED_LICENSE = "ODbL-1.0"


def fail(message: str) -> None:
    print(f"ANNEESSENS_AUTOMATIC_ROAD_SURFACE_SUPPORT_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def exact_number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"{label} is not an exact numeric JSON component")
    numeric = float(value)
    if not math.isfinite(numeric):
        fail(f"{label} is not finite")
    return numeric


def main() -> None:
    source = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    if source.get("source") != EXPECTED_SOURCE or source.get("license") != EXPECTED_LICENSE:
        fail("OSM source/provenance drifted")

    roads = source.get("roads")
    if not isinstance(roads, list):
        fail("roads collection missing")
    matches = [road for road in roads if isinstance(road, dict) and road.get("osm_id") == LEMONNIER_ID]
    if len(matches) != 1:
        fail(f"expected exactly one source road {LEMONNIER_ID}, got {len(matches)}")
    road = matches[0]
    if road.get("name") != "Boulevard Maurice Lemonnier - Maurice Lemonnierlaan":
        fail("Lemonnier source identity drifted")
    if road.get("class") != "tertiary" or road.get("drivable") is not True:
        fail("Lemonnier class/drivable contract drifted")

    raw_points = road.get("points")
    if not isinstance(raw_points, list) or len(raw_points) < 2:
        fail("Lemonnier source points missing")
    points: list[tuple[float, float]] = []
    for index, raw in enumerate(raw_points):
        if not isinstance(raw, list) or len(raw) != 2:
            fail(f"point[{index}] does not have exactly two components")
        points.append((exact_number(raw[0], f"point[{index}].x"), exact_number(raw[1], f"point[{index}].z")))

    best_index = -1
    best_length = -1.0
    for index, (start, finish) in enumerate(zip(points, points[1:])):
        length = math.dist(start, finish)
        if length > best_length:
            best_length = length
            best_index = index
    if best_index < 0 or best_length < 1.0:
        fail("no valid Lemonnier source segment")
    start = points[best_index]
    finish = points[best_index + 1]
    midpoint = ((start[0] + finish[0]) * 0.5, (start[1] + finish[1]) * 0.5)

    source_width = exact_number(road.get("width"), "road.width")
    display_width = max(source_width, 7.2)
    half_road = display_width * 0.5
    first_offset = half_road + 1.10
    sidewalk_width = 1.85
    sidewalk_inner = half_road + 0.10
    sidewalk_outer = sidewalk_inner + sidewalk_width
    if not (sidewalk_inner < first_offset < sidewalk_outer):
        fail(
            "resolver first candidate no longer lies inside the rendered tertiary sidewalk family: "
            f"offset={first_offset:.3f} sidewalk=[{sidewalk_inner:.3f},{sidewalk_outer:.3f}]"
        )

    builder = BUILDER_PATH.read_text(encoding="utf-8")
    resolver = RESOLVER_PATH.read_text(encoding="utf-8")

    # Validate the semantic contract rather than freezing the entire if-line.
    # Additional independently-authorized detail zones may join the predicate,
    # but Anneessens must continue to flow through the shared _is_detail_zone()
    # path and sidewalk generation must remain gated on drivable roads.
    road_detail_gate = re.search(
        r"if\s+\((?P<predicate>[^\n]+)\)\s+and\s+bool\(road\.get\(\"drivable\",\s*false\)\):\s*\n\s*_add_sidewalks\(root,\s*start,\s*finish,\s*width,\s*road_class\)",
        builder,
    )
    if road_detail_gate is None:
        fail("builder drivable visible-sidewalk gate is missing")
    predicate = road_detail_gate.group("predicate")
    if "_is_detail_zone(midpoint)" not in predicate:
        fail("shared Anneessens detail-zone predicate no longer gates sidewalk generation")

    for required in (
        "_add_sidewalks(root, start, finish, width, road_class)",
        "pavement.size = Vector3(sidewalk_width, 0.12, length)",
        "pavement.position = center + perpendicular * offset * side + Vector3(0, 0.085, 0)",
        "pavement.rotation.y = angle",
        "pavement.use_collision = false",
    ):
        if required not in builder:
            fail(f"builder visible-sidewalk contract drifted: {required}")
    for forbidden in (
        'ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"',
        "func _road_support_body(",
        "func _add_road_support_shape(",
        "road_support.add_child(support_collision)",
    ):
        if forbidden in builder:
            fail(f"visual builder duplicates canonical collision authority: {forbidden}")
    if "return osm_id <= 0" not in resolver:
        fail("positive road ids can bypass exact road-owned ground through canonical Ground")

    anchor_pattern = re.compile(
        r"^const\s+([A-Z0-9_]+)_ANCHOR\s*:=\s*Vector2\(\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*\)",
        re.MULTILINE,
    )
    radius_pattern = re.compile(
        r"^@export\s+var\s+([a-z0-9_]+)_detail_radius_m:\s*float\s*=\s*([0-9.]+)",
        re.MULTILINE,
    )
    anchors = {name.lower(): (float(x), float(z)) for name, x, z in anchor_pattern.findall(builder)}
    radii = {name: float(radius) for name, radius in radius_pattern.findall(builder)}
    detail_zones: list[tuple[str, tuple[float, float], float, float]] = []
    for name, anchor in anchors.items():
        radius = radii.get(name)
        if radius is None:
            continue
        distance = math.dist(midpoint, anchor)
        detail_zones.append((name, anchor, radius, distance))
    if not detail_zones:
        fail("no parseable builder detail zones")

    covering = [entry for entry in detail_zones if entry[3] <= entry[2]]
    if not covering:
        nearest = min(detail_zones, key=lambda entry: entry[3] - entry[2])
        fail(
            "source-backed Lemonnier direct-entry candidate has no visible sidewalk zone: "
            f"osm_id={LEMONNIER_ID} segment={best_index} midpoint=({midpoint[0]:.3f},{midpoint[1]:.3f}) "
            f"segment_length={best_length:.3f}m first_offset={first_offset:.3f}m "
            f"nearest_zone={nearest[0]} distance={nearest[3]:.3f}m radius={nearest[2]:.3f}m "
            "rendered_sidewalk=false"
        )

    zones = ",".join(sorted(entry[0] for entry in covering))
    print(
        "ANNEESSENS_AUTOMATIC_ROAD_SURFACE_SUPPORT_OK: "
        f"osm_id={LEMONNIER_ID} segment={best_index} midpoint=({midpoint[0]:.3f},{midpoint[1]:.3f}) "
        f"first_offset={first_offset:.3f}m sidewalk=[{sidewalk_inner:.3f},{sidewalk_outer:.3f}] "
        f"covering_detail_zones={zones} collision_authority=canonical-runtime source=OSM license={EXPECTED_LICENSE}"
    )


if __name__ == "__main__":
    main()
