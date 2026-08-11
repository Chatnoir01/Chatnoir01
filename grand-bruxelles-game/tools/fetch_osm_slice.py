#!/usr/bin/env python3
"""Fetch a small OpenStreetMap extract for the Grand Bruxelles vertical slice.

The output is raw working data. It must be cleaned and transformed before being
used as game geometry. Keep OpenStreetMap attribution and ODbL obligations in
mind when distributing derived databases.
"""

from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from pathlib import Path

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
USER_AGENT = "GrandBruxellesGame/0.1 (development geodata fetcher)"
DEFAULT_BBOX = (50.8330, 4.3330, 50.8515, 4.3575)


def build_query(bbox: tuple[float, float, float, float]) -> str:
    south, west, north, east = bbox
    box = f"{south},{west},{north},{east}"
    return f"""
[out:json][timeout:60];
(
  way[\"highway\"]({box});
  way[\"building\"]({box});
  relation[\"building\"]({box});
  way[\"railway\"]({box});
  way[\"leisure\"]({box});
  way[\"landuse\"]({box});
);
out geom;
""".strip()


def fetch(query: str) -> dict:
    payload = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(
        OVERPASS_URL,
        data=payload,
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.load(response)


def parse_bbox(raw: str) -> tuple[float, float, float, float]:
    values = tuple(float(part.strip()) for part in raw.split(","))
    if len(values) != 4:
        raise argparse.ArgumentTypeError("bbox must be south,west,north,east")
    south, west, north, east = values
    if south >= north or west >= east:
        raise argparse.ArgumentTypeError("bbox bounds are inverted")
    return south, west, north, east


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch the Brussels vertical-slice OSM extract")
    parser.add_argument(
        "--bbox",
        type=parse_bbox,
        default=DEFAULT_BBOX,
        help="south,west,north,east",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/osm/vertical_slice_01.raw.json"),
    )
    args = parser.parse_args()

    query = build_query(args.bbox)
    data = fetch(query)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

    print(f"saved {len(data.get('elements', []))} OSM elements to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
