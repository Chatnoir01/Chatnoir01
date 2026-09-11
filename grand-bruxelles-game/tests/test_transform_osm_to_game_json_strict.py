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

    for invalid_origin in ("nan,4.348", "90.0001,4.348", "50.84,180.0001"):
        try:
            transform_osm_to_game.parse_origin(invalid_origin)
        except Exception:
            pass
        else:
            raise AssertionError(f"invalid WGS84 origin accepted: {invalid_origin}")

    railway_only = {
        "elements": [
            {
                "type": "way",
                "id": 910001,
                "tags": {"railway": "rail"},
                "geometry": [
                    {"lat": 50.8419, "lon": 4.3480},
                    {"lat": 50.8429, "lon": 4.3490},
                ],
            }
        ]
    }
    railway_output = transform_osm_to_game.convert(railway_only, transform_osm_to_game.DEFAULT_ORIGIN)
    assert railway_output["stats"]["railways"] == 1
    assert railway_output["bounds_m"] != [0.0, 0.0, 0.0, 0.0], (
        "railway-only source geometry must contribute to deterministic output bounds"
    )

    print("TRANSFORM_OSM_JSON_STRICT_OK duplicate_keys_rejected=true constants_rejected=true float_overflow_rejected=true osm_identity_validated=true duplicate_osm_identity_rejected=true geometry_coordinate_pair_required=true node_coordinate_pair_required=true wgs84_ranges_required=true finite_origin_required=true railway_bounds_accounted=true network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
