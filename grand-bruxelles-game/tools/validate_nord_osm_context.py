#!/usr/bin/env python3
"""Validate Gare du Nord OSM context before any runtime binding.

This gate deliberately proves only geospatial context. It does not claim surveyed
building heights, station facade fidelity, photo-match, or JOUABLE promotion.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

EXPECTED_FORMAT = "grand-bruxelles-osm-v1"
EXPECTED_LICENSE = "ODbL-1.0"
EXPECTED_ORIGIN = (50.860637490313074, 4.361650664440722)
MAX_ORIGIN_ERROR = 1e-10
MIN_ROADS = 20
MIN_BUILDINGS = 20
MIN_RAILWAYS = 1
MIN_ENVIRONMENT_POINTS = 1


def fail(message: str) -> None:
    raise SystemExit(f"NORD_OSM_CONTEXT_FAIL {message}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("game_json", type=Path)
    args = parser.parse_args()

    if not args.game_json.is_file():
        fail(f"missing={args.game_json}")

    data = json.loads(args.game_json.read_text(encoding="utf-8"))
    if data.get("format") != EXPECTED_FORMAT:
        fail(f"format={data.get('format')!r}")
    if data.get("license") != EXPECTED_LICENSE:
        fail(f"license={data.get('license')!r}")
    if "OpenStreetMap" not in str(data.get("source", "")):
        fail(f"source={data.get('source')!r}")

    origin = data.get("origin") or {}
    lat = float(origin.get("lat", 999.0))
    lon = float(origin.get("lon", 999.0))
    if abs(lat - EXPECTED_ORIGIN[0]) > MAX_ORIGIN_ERROR or abs(lon - EXPECTED_ORIGIN[1]) > MAX_ORIGIN_ERROR:
        fail(f"origin=({lat},{lon})")

    stats = data.get("stats") or {}
    roads = int(stats.get("roads", 0))
    buildings = int(stats.get("buildings", 0))
    railways = int(stats.get("railways", 0))
    environment_points = int(stats.get("environment_points", 0))
    if roads < MIN_ROADS:
        fail(f"roads={roads}")
    if buildings < MIN_BUILDINGS:
        fail(f"buildings={buildings}")
    if railways < MIN_RAILWAYS:
        fail(f"railways={railways}")
    if environment_points < MIN_ENVIRONMENT_POINTS:
        fail(f"environment_points={environment_points}")

    bounds = data.get("bounds_m") or []
    if len(bounds) != 4:
        fail(f"bounds_m={bounds!r}")
    if not (float(bounds[0]) < 0.0 < float(bounds[2]) and float(bounds[1]) < 0.0 < float(bounds[3])):
        fail(f"origin_not_inside_bounds bounds_m={bounds!r}")

    print(
        "NORD_OSM_CONTEXT_OK "
        f"roads={roads} buildings={buildings} railways={railways} "
        f"environment_points={environment_points} origin={lat},{lon} "
        "runtime_bound=false photo_match=false promotion=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
