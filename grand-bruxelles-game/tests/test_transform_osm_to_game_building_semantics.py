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


def _expect_height_rejection(extra_tags: dict[str, str], expected_fragment: str) -> None:
    witness = _closed_square("yes", extra_tags=extra_tags)
    try:
        transform_osm_to_game.convert(witness, transform_osm_to_game.DEFAULT_ORIGIN)
    except ValueError as exc:
        assert expected_fragment in str(exc).lower(), exc
    else:
        raise AssertionError(
            f"explicit OSM building height metadata {extra_tags!r} must fail closed instead of silently falling back"
        )


def main() -> int:
    negative = transform_osm_to_game.convert(_closed_square("no"), transform_osm_to_game.DEFAULT_ORIGIN)
    assert negative["stats"]["buildings"] == 0, (
        "building=no is an explicit negative OSM semantic and must not be materialized as a building"
    )

    positive = transform_osm_to_game.convert(_closed_square("yes"), transform_osm_to_game.DEFAULT_ORIGIN)
    assert positive["stats"]["buildings"] == 1, "building=yes must remain eligible"

    _expect_height_rejection({"height": "12 metres??"}, "building height")
    _expect_height_rejection({"height": "500"}, "building height")
    _expect_height_rejection({"height": "1"}, "building height")
    _expect_height_rejection({"building:levels": "many"}, "building levels")
    _expect_height_rejection({"building:levels": "0"}, "building levels")
    _expect_height_rejection({"building:levels": "81"}, "building levels")

    explicit_valid_height = transform_osm_to_game.convert(
        _closed_square("yes", extra_tags={"height": "12 m"}),
        transform_osm_to_game.DEFAULT_ORIGIN,
    )
    assert explicit_valid_height["buildings"][0]["height"] == 12.0

    absent_height = transform_osm_to_game.convert(_closed_square("yes"), transform_osm_to_game.DEFAULT_ORIGIN)
    assert absent_height["buildings"][0]["height"] == 10.5

    print(
        "TRANSFORM_OSM_BUILDING_SEMANTICS_OK "
        "explicit_negative_building_rejected=true positive_building_retained=true "
        "malformed_height_rejected=true out_of_range_height_rejected=true "
        "invalid_levels_rejected=true valid_explicit_height_retained=true "
        "absent_height_fallback_retained=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
