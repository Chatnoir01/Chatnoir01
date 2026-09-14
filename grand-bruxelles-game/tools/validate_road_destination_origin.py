#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ROAD_DESTINATION_ORIGIN_FAIL: {message}")


def validate(payload: Any) -> tuple[float, float]:
    if type(payload) is not dict:
        fail("source root must be an object")
    if payload.get("format") != "grand-bruxelles-osm-v1":
        fail("source format drift")
    if payload.get("source") != "OpenStreetMap contributors via Overpass API":
        fail("source attribution drift")
    if payload.get("license") != "ODbL-1.0":
        fail("source license drift")

    origin = payload.get("origin")
    if type(origin) is not dict or set(origin) != {"lat", "lon"}:
        fail("origin must contain exactly lat and lon")

    values: list[float] = []
    for key, minimum, maximum in (("lat", -90.0, 90.0), ("lon", -180.0, 180.0)):
        raw = origin.get(key)
        if type(raw) not in (int, float):
            fail(f"origin.{key} must be a JSON number")
        value = float(raw)
        if not math.isfinite(value):
            fail(f"origin.{key} must be finite")
        if value < minimum or value > maximum:
            fail(f"origin.{key} outside WGS84 range")
        values.append(value)
    return values[0], values[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()
    try:
        payload = json.loads(args.source.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"invalid source JSON: {exc}")
    lat, lon = validate(payload)
    print(f"ROAD_DESTINATION_ORIGIN_OK lat={lat:.7f} lon={lon:.7f} network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
