#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import urllib.request
from pathlib import Path
from typing import Any

EARTH_RADIUS_M = 6_378_137.0
ORIGIN = (50.8419, 4.3480)
OSM_ID = 256375327
SOURCE_URL = f"https://api.openstreetmap.org/api/0.6/way/{OSM_ID}/full.json"
USER_AGENT = "GrandBruxellesGame/0.2 (source-backed Anneessens landmark fetcher)"
VERTICAL_TAGS = ("height", "building:levels", "roof:height", "roof:levels", "roof:shape")


def metric_point(lat: float, lon: float) -> list[float]:
    lat0 = math.radians(ORIGIN[0])
    x = math.radians(lon - ORIGIN[1]) * EARTH_RADIUS_M * math.cos(lat0)
    north = math.radians(lat - ORIGIN[0]) * EARTH_RADIUS_M
    return [round(x, 3), round(-north, 3)]


def fetch() -> dict[str, Any]:
    request = urllib.request.Request(
        SOURCE_URL,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = json.load(response)
    if not isinstance(payload, dict) or not isinstance(payload.get("elements"), list):
        raise RuntimeError("OSM API returned an invalid payload")
    return payload


def build_snapshot(payload: dict[str, Any]) -> dict[str, Any]:
    nodes: dict[int, tuple[float, float]] = {}
    way: dict[str, Any] | None = None
    for element in payload["elements"]:
        if element.get("type") == "node" and "lat" in element and "lon" in element:
            nodes[int(element["id"])] = (float(element["lat"]), float(element["lon"]))
        elif element.get("type") == "way" and int(element.get("id", 0)) == OSM_ID:
            way = element
    if way is None:
        raise RuntimeError(f"OSM way {OSM_ID} missing from full response")
    refs = [int(value) for value in way.get("nodes", [])]
    if len(refs) < 4 or refs[0] != refs[-1]:
        raise RuntimeError("Anneessens school OSM way is not a closed building polygon")
    if any(ref not in nodes for ref in refs):
        raise RuntimeError("Anneessens school OSM way has unresolved node references")
    footprint = [metric_point(*nodes[ref]) for ref in refs[:-1]]
    tags = way.get("tags", {}) or {}
    vertical_tags = {key: tags[key] for key in VERTICAL_TAGS if key in tags}
    return {
        "format": "grand-bruxelles-hero-source-v1",
        "source": "OpenStreetMap contributors",
        "license": "ODbL-1.0",
        "osm_type": "way",
        "osm_id": OSM_ID,
        "source_url": SOURCE_URL,
        "source_version": int(way.get("version", 0)),
        "source_timestamp": str(way.get("timestamp", "")),
        "name": str(tags.get("name", "")),
        "building": str(tags.get("building", "")),
        "amenity": str(tags.get("amenity", "")),
        "vertical_tags": vertical_tags,
        "footprint": footprint,
        "heritage_contract": {
            "source": "monument.heritage.brussels",
            "record": "Ancienne école communale n° 13, place Anneessens 11",
            "main_facade_bays": 5,
            "projecting_gabled_bays": [2, 4],
            "central_loggia": True,
            "brick_with_white_and_blue_stone": True,
            "slate_roof": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    snapshot = build_snapshot(fetch())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":"))
    args.output.write_text(text, encoding="utf-8")
    print("ANNEESSENS_SOURCE_JSON=" + text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
