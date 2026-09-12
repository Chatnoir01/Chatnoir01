#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


def _closed_square(*, extra_tags: dict[str, str]) -> dict[str, object]:
    tags = {"building": "yes", "name": "Explicit dimension witness"}
    tags.update(extra_tags)
    return {
        "elements": [
            {
                "type": "way",
                "id": 3402,
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


def _expect_rejected(tags: dict[str, str], expected_fragment: str) -> None:
    try:
        transform_osm_to_game.convert(_closed_square(extra_tags=tags), transform_osm_to_game.DEFAULT_ORIGIN)
    except ValueError as exc:
        assert expected_fragment in str(exc).lower(), exc
    else:
        raise AssertionError(
            f"explicit invalid source dimension {tags!r} must fail closed instead of falling back to an invented default"
        )


def main() -> int:
    _expect_rejected({"height": "0"}, "building height")
    _expect_rejected({"height": "300"}, "building height")
    _expect_rejected({"building:levels": "0"}, "building levels")
    _expect_rejected({"building:levels": "81"}, "building levels")

    valid_height = transform_osm_to_game.convert(
        _closed_square(extra_tags={"height": "12"}), transform_osm_to_game.DEFAULT_ORIGIN
    )
    assert valid_height["buildings"][0]["height"] == 12.0

    valid_levels = transform_osm_to_game.convert(
        _closed_square(extra_tags={"building:levels": "4"}), transform_osm_to_game.DEFAULT_ORIGIN
    )
    assert valid_levels["buildings"][0]["height"] == 12.6

    print(
        "TRANSFORM_OSM_EXPLICIT_DIMENSIONS_OK "
        "out_of_range_height_rejected=true out_of_range_levels_rejected=true "
        "valid_height_retained=true valid_levels_retained=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
