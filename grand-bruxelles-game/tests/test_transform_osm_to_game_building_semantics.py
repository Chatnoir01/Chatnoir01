#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


def _closed_square(building_value: str) -> dict[str, object]:
    return {
        "elements": [
            {
                "type": "way",
                "id": 3401,
                "tags": {"building": building_value, "name": "Negative building semantic witness"},
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

    print(
        "TRANSFORM_OSM_BUILDING_SEMANTICS_OK "
        "explicit_negative_building_rejected=true positive_building_retained=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
