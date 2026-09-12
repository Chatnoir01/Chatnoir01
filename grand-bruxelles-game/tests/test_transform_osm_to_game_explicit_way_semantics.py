#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


FALSE_LIKE = ("no", "false", "0", "none")
HIGHWAY_NON_OPERATIONAL_LIFECYCLE = ("construction", "proposed")
RAILWAY_NON_OPERATIONAL_LIFECYCLE = (
    "construction",
    "proposed",
    "disused",
    "abandoned",
    "razed",
    "dismantled",
)
LIFECYCLE_STATE_FLAGS = ("disused", "abandoned")
LIFECYCLE_SHADOW_PREFIXES = ("construction", "proposed", "disused", "abandoned")


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

    for raw in HIGHWAY_NON_OPERATIONAL_LIFECYCLE:
        converted = transform_osm_to_game.convert(
            _way({"highway": raw, "construction": "residential", "name": "Lifecycle highway witness"}),
            transform_osm_to_game.DEFAULT_ORIGIN,
        )
        assert converted["roads"] == [], (
            f"non-operational highway={raw!r} must not materialize into the active road catalog"
        )

    for raw in RAILWAY_NON_OPERATIONAL_LIFECYCLE:
        converted = transform_osm_to_game.convert(
            _way({"railway": raw, "construction": "rail", "name": "Lifecycle railway witness"}),
            transform_osm_to_game.DEFAULT_ORIGIN,
        )
        assert converted["railways"] == [], (
            f"non-operational railway={raw!r} must not materialize into the active railway catalog"
        )

    for lifecycle_flag in LIFECYCLE_STATE_FLAGS:
        converted = transform_osm_to_game.convert(
            _way({
                "highway": "residential",
                lifecycle_flag: "yes",
                "name": "Lifecycle-state highway witness",
            }),
            transform_osm_to_game.DEFAULT_ORIGIN,
        )
        assert converted["roads"] == [], (
            f"highway=residential + {lifecycle_flag}=yes must not materialize into the active road catalog"
        )

        converted = transform_osm_to_game.convert(
            _way({
                "railway": "rail",
                lifecycle_flag: "yes",
                "name": "Lifecycle-state railway witness",
            }),
            transform_osm_to_game.DEFAULT_ORIGIN,
        )
        assert converted["railways"] == [], (
            f"railway=rail + {lifecycle_flag}=yes must not materialize into the active railway catalog"
        )

    for lifecycle_prefix in LIFECYCLE_SHADOW_PREFIXES:
        converted = transform_osm_to_game.convert(
            _way({
                "highway": "residential",
                f"{lifecycle_prefix}:highway": "residential",
                "name": "Lifecycle-shadow highway witness",
            }),
            transform_osm_to_game.DEFAULT_ORIGIN,
        )
        assert converted["roads"] == [], (
            f"conflicting active highway + {lifecycle_prefix}:highway must fail closed"
        )

        converted = transform_osm_to_game.convert(
            _way({
                "railway": "rail",
                f"{lifecycle_prefix}:railway": "rail",
                "name": "Lifecycle-shadow railway witness",
            }),
            transform_osm_to_game.DEFAULT_ORIGIN,
        )
        assert converted["railways"] == [], (
            f"conflicting active railway + {lifecycle_prefix}:railway must fail closed"
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
        "lifecycle_highway_rejected=true lifecycle_railway_rejected=true "
        "retired_railway_rejected=true lifecycle_state_flags_rejected=true "
        "lifecycle_shadow_conflicts_rejected=true "
        "positive_controls_retained=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
