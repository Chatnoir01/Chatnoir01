#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


FALSE_LIKE = ("no", "false", "0", "none")


def _way(tags: dict[str, str]) -> dict[str, object]:
    return {
        "elements": [
            {
                "type": "way",
                "id": 5501,
                "tags": tags,
                "geometry": [
                    {"lat": 50.8410, "lon": 4.3470},
                    {"lat": 50.8420, "lon": 4.3470},
                ],
            }
        ]
    }


def main() -> int:
    for raw in FALSE_LIKE:
        converted = transform_osm_to_game.convert(
            _way({"highway": raw, "name": "Explicit negative highway witness"}),
            transform_osm_to_game.DEFAULT_ORIGIN,
        )
        assert converted["roads"] == [], (
            f"explicit negative highway={raw!r} must not materialize a road"
        )

        converted = transform_osm_to_game.convert(
            _way({"railway": raw, "name": "Explicit negative railway witness"}),
            transform_osm_to_game.DEFAULT_ORIGIN,
        )
        assert converted["railways"] == [], (
            f"explicit negative railway={raw!r} must not materialize a railway"
        )

    positive_road = transform_osm_to_game.convert(
        _way({"highway": "residential", "name": "Positive road control"}),
        transform_osm_to_game.DEFAULT_ORIGIN,
    )
    assert len(positive_road["roads"]) == 1
    assert positive_road["roads"][0]["class"] == "residential"

    positive_rail = transform_osm_to_game.convert(
        _way({"railway": "rail", "name": "Positive railway control"}),
        transform_osm_to_game.DEFAULT_ORIGIN,
    )
    assert len(positive_rail["railways"]) == 1
    assert positive_rail["railways"][0]["class"] == "rail"

    print(
        "TRANSFORM_OSM_EXPLICIT_WAY_SEMANTICS_OK "
        "negative_highway_rejected=true negative_railway_rejected=true "
        "positive_controls_retained=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
