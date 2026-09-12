#!/usr/bin/env python3
from __future__ import annotations

import math
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


def _road(*, lanes: str) -> dict[str, object]:
    return {
        "elements": [
            {
                "type": "way",
                "id": 4402,
                "tags": {
                    "highway": "residential",
                    "name": "Explicit lanes witness",
                    "lanes": lanes,
                },
                "geometry": [
                    {"lat": 50.8410, "lon": 4.3470},
                    {"lat": 50.8420, "lon": 4.3470},
                ],
            }
        ]
    }


def _expect_rejected(raw_lanes: str) -> None:
    try:
        transform_osm_to_game.convert(_road(lanes=raw_lanes), transform_osm_to_game.DEFAULT_ORIGIN)
    except ValueError as exc:
        assert "road lanes" in str(exc).lower() or "road width" in str(exc).lower(), exc
    else:
        raise AssertionError(
            f"explicit invalid lanes={raw_lanes!r} must fail closed instead of producing an invalid width"
        )


def main() -> int:
    for raw_lanes in ("bogus", "nan", "0", "-2"):
        _expect_rejected(raw_lanes)

    # A syntactically finite OSM numeric value can still overflow when the
    # derived carriageway width multiplies lane count by 3m. The converter
    # must reject that derivation instead of emitting Infinity into game JSON.
    _expect_rejected("1e308")

    one_lane = transform_osm_to_game.convert(_road(lanes="1"), transform_osm_to_game.DEFAULT_ORIGIN)
    assert one_lane["roads"][0]["width"] == 5.6
    assert math.isfinite(one_lane["roads"][0]["width"])

    three_lanes = transform_osm_to_game.convert(_road(lanes="3"), transform_osm_to_game.DEFAULT_ORIGIN)
    assert three_lanes["roads"][0]["width"] == 9.0
    assert math.isfinite(three_lanes["roads"][0]["width"])

    print(
        "TRANSFORM_OSM_EXPLICIT_LANES_OK "
        "invalid_explicit_lanes_rejected=true nonpositive_lanes_rejected=true "
        "derived_width_overflow_rejected=true valid_lane_widths_retained=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
