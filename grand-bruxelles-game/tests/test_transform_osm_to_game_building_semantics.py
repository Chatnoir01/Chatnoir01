#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


def _closed_square(building_value: str, *, extra_tags: dict[str, str] | None = None) -> dict[str, object]:
    tags = {"building": building_value, "name": "Building semantic witness"}
    if extra_tags:
        tags.update(extra_tags)
    return {
        "elements": [
            {
                "type": "way",
                "id": 3401,
                "tags": tags,
                "geometry": [
                    {"lat": 50.8410, "lon": 4.3470},
                    {"lat": 50.8410, "lon": 4.3480},
                    {"lat": 50.8420, "lon": 4.3480},
                    {"lat": 50.8420, "lon": 4.3470},
                    {"lat": 50.8410, "lon": 4.3470},
                ],
            }
        ]
    }


def _assert_not_materialized(payload: dict[str, object], label: str) -> None:
    converted = transform_osm_to_game.convert(payload, transform_osm_to_game.DEFAULT_ORIGIN)
    assert converted["stats"]["buildings"] == 0, label


def main() -> int:
    _assert_not_materialized(
        _closed_square("no"),
        "building=no is an explicit negative OSM semantic and must not be materialized as a building",
    )

    # Lifecycle values and lifecycle-prefixed shadows describe non-operational / historical
    # building state. They must never enter the active building catalog merely because the
    # geometry is closed and otherwise valid.
    _assert_not_materialized(
        _closed_square("construction"),
        "building=construction must not be materialized as an active building",
    )
    _assert_not_materialized(
        _closed_square("proposed"),
        "building=proposed must not be materialized as an active building",
    )
    for lifecycle_prefix in ("construction", "proposed", "disused", "abandoned"):
        _assert_not_materialized(
            _closed_square("yes", extra_tags={f"{lifecycle_prefix}:building": "house"}),
            f"{lifecycle_prefix}:building must shadow building=yes out of the active building catalog",
        )
    for state_flag in ("disused", "abandoned"):
        _assert_not_materialized(
            _closed_square("yes", extra_tags={state_flag: "yes"}),
            f"{state_flag}=yes must keep building=yes out of the active building catalog",
        )

    positive = transform_osm_to_game.convert(_closed_square("yes"), transform_osm_to_game.DEFAULT_ORIGIN)
    assert positive["stats"]["buildings"] == 1, "building=yes must remain eligible"

    malformed_height = _closed_square("yes", extra_tags={"height": "12 metres??"})
    try:
        transform_osm_to_game.convert(malformed_height, transform_osm_to_game.DEFAULT_ORIGIN)
    except ValueError as exc:
        assert "building height" in str(exc).lower(), exc
    else:
        raise AssertionError(
            "a present malformed OSM building height must fail closed instead of silently falling back to a default height"
        )

    print(
        "TRANSFORM_OSM_BUILDING_SEMANTICS_OK "
        "explicit_negative_building_rejected=true lifecycle_buildings_rejected=true "
        "positive_building_retained=true malformed_height_rejected=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
