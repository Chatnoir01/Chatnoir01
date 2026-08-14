#!/usr/bin/env python3
"""Fetch one STIB/MIVB stop from the official Brussels Mobility OGC API.

Discovery only: this script does not change runtime geography. It prints a compact
source record so a later commit can lock the exact official stop point.
"""

from __future__ import annotations

import json
import sys
import urllib.parse
import urllib.request

BASE = (
    "https://data.mobility.brussels/geoserver/ogc/features/v1/collections/"
    "bm_public_transport%3Astib_stops/items"
)
TARGET_STOP_ID = "2539"
EXPECTED_FR = "Suède"
EXPECTED_NL = "Zweden"


def fetch_page(start_index: int, limit: int = 500) -> dict:
    query = urllib.parse.urlencode(
        {"f": "application/geo+json", "limit": str(limit), "startIndex": str(start_index)}
    )
    request = urllib.request.Request(
        f"{BASE}?{query}",
        headers={"User-Agent": "Grand-Bruxelles-Game-source-audit/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main() -> int:
    start = 0
    page_size = 500
    while start < 5000:
        payload = fetch_page(start, page_size)
        features = payload.get("features", [])
        if not isinstance(features, list):
            raise RuntimeError("official OGC response has no feature array")
        for feature in features:
            props = feature.get("properties", {})
            if str(props.get("stop_id", "")) != TARGET_STOP_ID:
                continue
            name_fr = str(props.get("name_fr", ""))
            name_nl = str(props.get("name_nl", ""))
            if name_fr.casefold() != EXPECTED_FR.casefold() or name_nl.casefold() != EXPECTED_NL.casefold():
                raise RuntimeError(
                    f"stop {TARGET_STOP_ID} identity drift: {name_fr!r} / {name_nl!r}"
                )
            geometry = feature.get("geometry")
            if not isinstance(geometry, dict) or geometry.get("type") != "Point":
                raise RuntimeError("Suède stop geometry is not a GeoJSON Point")
            coordinates = geometry.get("coordinates", [])
            if not isinstance(coordinates, list) or len(coordinates) < 2:
                raise RuntimeError("Suède stop has no usable coordinates")
            record = {
                "schema": "grand-bruxelles-stib-stop-source-probe-v1",
                "authority": "Brussels Mobility / STIB-MIVB",
                "collection": "bm_public_transport:stib_stops",
                "stop_id": TARGET_STOP_ID,
                "name_fr": name_fr,
                "name_nl": name_nl,
                "mode": props.get("mode"),
                "lines": props.get("line"),
                "feature_id": feature.get("id"),
                "geojson_coordinates": coordinates[:2],
                "geojson_default_crs": "OGC API Features default CRS84",
                "runtime_approved": False,
            }
            print("STIB_SUEDE_SOURCE_OK=" + json.dumps(record, ensure_ascii=False, sort_keys=True))
            return 0
        if len(features) < page_size:
            break
        start += page_size
    print(f"STIB_SUEDE_SOURCE_FAIL: stop_id={TARGET_STOP_ID} not found", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
