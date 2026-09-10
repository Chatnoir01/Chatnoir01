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

    require_rejected(
        '{"elements":[{"type":"way","id":1}],"elements":[]}',
        "duplicate elements",
    )
    require_rejected(
        '{"elements":[{"type":"node","id":1,"lat":NaN,"lon":4.34}]}',
        "NaN constant",
    )
    require_rejected(
        '{"elements":[{"type":"node","id":1,"lat":1e309,"lon":4.34}]}',
        "finite-syntax float overflow",
    )

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "ok.json"
        path.write_text('{"version":0.6,"elements":[]}', encoding="utf-8")
        payload = transform_osm_to_game.load_source_json(path)
    assert payload == {"version": 0.6, "elements": []}
    assert math.isfinite(payload["version"])

    try:
        transform_osm_to_game.parse_origin("nan,4.348")
    except Exception:
        pass
    else:
        raise AssertionError("non-finite origin accepted")

    print("TRANSFORM_OSM_JSON_STRICT_OK duplicate_keys_rejected=true constants_rejected=true float_overflow_rejected=true finite_origin_required=true network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
