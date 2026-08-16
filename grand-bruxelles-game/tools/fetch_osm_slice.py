#!/usr/bin/env python3
"""Fetch a small OpenStreetMap extract for the Grand Bruxelles vertical slice.

The output is raw working data. It must be cleaned and transformed before being
used as game geometry. Keep OpenStreetMap attribution and ODbL obligations in
mind when distributing derived databases.
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
USER_AGENT = "GrandBruxellesGame/0.2 (development geodata fetcher)"
DEFAULT_BBOX = (50.8330, 4.3330, 50.8515, 4.3575)
TRANSIENT_HTTP_CODES = {408, 425, 429, 500, 502, 503, 504}


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
  node[\"natural\"=\"tree\"]({box});
  node[\"highway\"=\"street_lamp\"]({box});
  node[\"barrier\"=\"bollard\"]({box});
);
out geom;
""".strip()


def _request(query: str) -> dict:
    payload = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(
        OVERPASS_URL,
        data=payload,
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=100) as response:
        return json.load(response)


def fetch(query: str, retries: int = 4) -> dict:
    """Fetch Overpass data with bounded exponential retry for transient errors."""
    if retries < 1:
        raise ValueError("retries must be at least 1")

    for attempt in range(1, retries + 1):
        try:
            data = _request(query)
            if not isinstance(data, dict) or "elements" not in data:
                raise ValueError("Overpass returned an unexpected JSON payload")
            return data
        except urllib.error.HTTPError as exc:
            retryable = exc.code in TRANSIENT_HTTP_CODES
            if not retryable or attempt == retries:
                raise
            delay = min(2 ** attempt, 12)
            print(f"Overpass HTTP {exc.code}; retry {attempt}/{retries} in {delay}s")
            time.sleep(delay)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            if attempt == retries:
                raise
            delay = min(2 ** attempt, 12)
            print(f"Overpass transient error {exc!r}; retry {attempt}/{retries} in {delay}s")
            time.sleep(delay)

    raise RuntimeError("unreachable: Overpass retry loop exhausted")


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
    parser.add_argument(
        "--retries",
        type=int,
        default=4,
        help="number of bounded Overpass attempts (default: 4)",
    )
    args = parser.parse_args()

    query = build_query(args.bbox)
    data = fetch(query, retries=args.retries)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

    element_count = len(data.get("elements", []))
    if element_count == 0:
        raise RuntimeError("Overpass returned zero elements for the Brussels slice")
    print(f"saved {element_count} OSM elements to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
