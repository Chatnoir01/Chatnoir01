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


def main() -> int:
    negative = transform_osm_to_game.convert(_closed_square("no"), transform_osm_to_game.DEFAULT_ORIGIN)
    assert negative["stats"]["buildings"] == 0, (
        "building=no is an explicit negative OSM semantic and must not be materialized as a building"
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
        "explicit_negative_building_rejected=true positive_building_retained=true "
        "malformed_height_rejected=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
