#!/usr/bin/env python3
from __future__ import annotations

import json
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
    raise AssertionError(f"OSM transform accepted non-numeric JSON coordinate type: {label}")


def main() -> int:
    # Overpass coordinate members are numeric JSON values. Numeric-looking strings must
    # not silently cross the source-schema boundary because later exact-source closure
    # and provenance checks operate on the parsed source representation.
    require_rejected(
        '{"elements":[{"type":"node","id":701,"lat":"50.841","lon":4.348}]}',
        "node latitude string",
    )
    require_rejected(
        '{"elements":[{"type":"node","id":702,"lat":50.841,"lon":"4.348"}]}',
        "node longitude string",
    )
    require_rejected(
        '{"elements":[{"type":"way","id":703,"geometry":[{"lat":"50.841","lon":4.348},{"lat":50.842,"lon":4.349}]}]}',
        "geometry latitude string",
    )
    require_rejected(
        '{"elements":[{"type":"way","id":704,"geometry":[{"lat":50.841,"lon":"4.348"},{"lat":50.842,"lon":4.349}]}]}',
        "geometry longitude string",
    )

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "ok.json"
        path.write_text(
            '{"elements":[{"type":"node","id":705,"lat":50.841,"lon":4.348},'
            '{"type":"way","id":706,"geometry":[{"lat":50,"lon":4},{"lat":50.1,"lon":4.1}]}]}',
            encoding="utf-8",
        )
        payload = transform_osm_to_game.load_source_json(path)
    assert len(payload["elements"]) == 2

    print(
        "TRANSFORM_OSM_COORDINATE_JSON_TYPES_OK "
        "numeric_strings_rejected=true json_numbers_retained=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
