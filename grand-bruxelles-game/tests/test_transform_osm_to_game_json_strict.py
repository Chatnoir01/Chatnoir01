#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


def require_rejected(raw: str, label: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "source.json"
        path.write_text(raw, encoding="utf-8")
        try:
            transform_osm_to_game.load_source_json(path)
        except (ValueError, json.JSONDecodeError, UnicodeDecodeError):
            return
    raise AssertionError(f"OSM transform accepted ambiguous/non-finite source JSON: {label}")


def main() -> int:
    if not hasattr(transform_osm_to_game, "load_source_json"):
        raise AssertionError("strict source loader is missing")

    require_rejected('{"elements":[{"type":"way","id":1}],"elements":[]}', "duplicate elements key")
    require_rejected('{"elements":[{"type":"node","id":1,"lat":NaN,"lon":4.34}]}', "NaN constant")
    require_rejected('{"elements":[{"type":"node","id":1,"lat":1e309,"lon":4.34}]}', "finite-syntax float overflow")
    require_rejected('{"elements":[{"type":"way","id":17},{"type":"way","id":17}]}', "duplicate OSM way identity")
    require_rejected('{"elements":[{"type":"node","id":"17","lat":50.84,"lon":4.34}]}', "string OSM id")
    require_rejected('{"elements":[{"type":"node","id":true,"lat":50.84,"lon":4.34}]}', "boolean OSM id")
    require_rejected('{"elements":[{"type":"way","id":0}]}', "non-positive OSM id")
    require_rejected('{"elements":[{"type":"mystery","id":19}]}', "unknown OSM element type")
    require_rejected('{"elements":[{"type":"way","id":20,"tags":{"highway":true}}]}', "boolean OSM tag value")
    require_rejected('{"elements":[{"type":"way","id":21,"tags":{"highway":{"class":"primary"}}}]}', "object OSM tag value")
    require_rejected('{"elements":[{"type":"node","id":22,"lat":50.84,"lon":4.34,"tags":{"name":17}}]}', "numeric OSM tag value")
    require_rejected('{"elements":[{"type":"way","id":23,"geometry":[{"lat":50.84,"lon":4.34},{"lat":50.85}]}]}', "geometry point missing longitude")
    require_rejected('{"elements":[{"type":"way","id":24,"geometry":[{"lat":50.84,"lon":4.34},{"lon":4.35}]}]}', "geometry point missing latitude")
    require_rejected('{"elements":[{"type":"node","id":25,"lon":4.35,"tags":{"natural":"tree"}}]}', "node missing latitude")
    require_rejected('{"elements":[{"type":"node","id":26,"lat":50.84,"tags":{"natural":"tree"}}]}', "node missing longitude")
    require_rejected('{"elements":[{"type":"node","id":27,"lat":90.0001,"lon":4.35}]}', "node latitude outside WGS84 range")
    require_rejected('{"elements":[{"type":"node","id":28,"lat":50.84,"lon":180.0001}]}', "node longitude outside WGS84 range")
    require_rejected('{"elements":[{"type":"way","id":29,"geometry":[{"lat":50.84,"lon":4.34},{"lat":-90.0001,"lon":4.35}]}]}', "geometry latitude outside WGS84 range")
    require_rejected('{"elements":[{"type":"way","id":30,"geometry":[{"lat":50.84,"lon":4.34},{"lat":50.85,"lon":-180.0001}]}]}', "geometry longitude outside WGS84 range")

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "ok.json"
        path.write_text('{"version":0.6,"elements":[{"type":"node","id":17,"lat":50.84,"lon":4.34},{"type":"way","id":17,"geometry":[]}]}', encoding="utf-8")
        payload = transform_osm_to_game.load_source_json(path)
    assert payload["version"] == 0.6
    assert len(payload["elements"]) == 2
    assert math.isfinite(payload["version"])

    assert transform_osm_to_game.numeric_tag({"lanes": "2m"}, "lanes") is None, "lanes must reject unit-suffixed values"
    assert transform_osm_to_game.numeric_tag({"layer": "1m"}, "layer") is None, "layer must reject unit-suffixed values"
    assert transform_osm_to_game.building_height({"height": "12mm"}) == 10.5, "millimetres must not be silently treated as metres"
    assert transform_osm_to_game.building_height({"height": "12 m"}) == 12.0, "explicit metre height must remain supported"

    railway_only = {
        "elements": [
            {
                "type": "way",
                "id": 31,
                "tags": {"railway": "rail"},
                "geometry": [
                    {"lat": 50.8410, "lon": 4.3470},
                    {"lat": 50.8420, "lon": 4.3490},
                ],
            }
        ]
    }
    railway_result = transform_osm_to_game.convert(railway_only, transform_osm_to_game.DEFAULT_ORIGIN)
    assert railway_result["stats"]["railways"] == 1
    railway_points = railway_result["railways"][0]["points"]
    expected_bounds = [
        round(min(point[0] for point in railway_points), 2),
        round(min(point[1] for point in railway_points), 2),
        round(max(point[0] for point in railway_points), 2),
        round(max(point[1] for point in railway_points), 2),
    ]
    assert railway_result["bounds_m"] == expected_bounds
    assert railway_result["bounds_m"] != [0.0, 0.0, 0.0, 0.0]

    railway_order_input = {
        "elements": [
            {
                "type": "way",
                "id": 90,
                "tags": {"railway": "tram", "name": "Zulu"},
                "geometry": [
                    {"lat": 50.8410, "lon": 4.3470},
                    {"lat": 50.8415, "lon": 4.3480},
                ],
            },
            {
                "type": "way",
                "id": 40,
                "tags": {"railway": "rail", "name": "Alpha"},
                "geometry": [
                    {"lat": 50.8420, "lon": 4.3490},
                    {"lat": 50.8425, "lon": 4.3500},
                ],
            },
        ]
    }
    railway_order_result = transform_osm_to_game.convert(railway_order_input, transform_osm_to_game.DEFAULT_ORIGIN)
    assert [(item["class"], item["osm_id"]) for item in railway_order_result["railways"]] == [
        ("rail", 40),
        ("tram", 90),
    ], "railway output must be deterministic independently of source element order"

    for invalid_origin in ("nan,4.348", "90.0001,4.348", "50.84,180.0001"):
        try:
            transform_osm_to_game.parse_origin(invalid_origin)
        except Exception:
            pass
        else:
            raise AssertionError(f"invalid WGS84 origin accepted: {invalid_origin}")

    print("TRANSFORM_OSM_JSON_STRICT_OK duplicate_keys_rejected=true constants_rejected=true float_overflow_rejected=true osm_identity_validated=true duplicate_osm_identity_rejected=true osm_tag_strings_required=true numeric_tag_units_strict=true geometry_coordinate_pair_required=true node_coordinate_pair_required=true wgs84_ranges_required=true railway_bounds_accounted=true railway_order_deterministic=true finite_origin_required=true network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
