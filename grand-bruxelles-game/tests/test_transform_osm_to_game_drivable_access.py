#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


def _way(tags: dict[str, str]) -> dict[str, object]:
    return {
        "elements": [
            {
                "type": "way",
                "id": 6601,
                "tags": tags,
                "geometry": [
                    {"lat": 50.8410, "lon": 4.3470},
                    {"lat": 50.8420, "lon": 4.3470},
                ],
            }
        ]
    }


def _drivable(tags: dict[str, str]) -> bool:
    converted = transform_osm_to_game.convert(
        _way(tags),
        transform_osm_to_game.DEFAULT_ORIGIN,
    )
    assert len(converted["roads"]) == 1
    return bool(converted["roads"][0]["drivable"])


def main() -> int:
    for restriction_key in ("access", "vehicle", "motor_vehicle", "motorcar"):
        assert _drivable({"highway": "residential", restriction_key: "no"}) is False, (
            f"explicit {restriction_key}=no must make a supported road non-drivable"
        )

    assert _drivable({"highway": "residential", "access": "no", "motor_vehicle": "yes"}) is True
    assert _drivable({"highway": "residential", "vehicle": "no", "motor_vehicle": "yes"}) is True
    assert _drivable({"highway": "residential", "motor_vehicle": "no", "motorcar": "yes"}) is True
    assert _drivable({"highway": "residential"}) is True

    print(
        "TRANSFORM_OSM_DRIVABLE_ACCESS_OK "
        "explicit_no_restrictions_rejected=true specificity_overrides_preserved=true "
        "positive_control_retained=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
