#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

from fetch_osm_slice import DEFAULT_BBOX, OVERPASS_URL, USER_AGENT
from make_runtime_slice import corridor_distance
from transform_osm_to_game import metric_point

KINDS = {
    ("natural", "tree"): "tree",
    ("highway", "street_lamp"): "street_lamp",
    ("barrier", "bollard"): "bollard",
}


def build_point_query(bbox: tuple[float, float, float, float]) -> str:
    south, west, north, east = bbox
    box = f"{south},{west},{north},{east}"
    return (
        "[out:json][timeout:60];("
        f'node["natural"="tree"]({box});'
        f'node["highway"="street_lamp"]({box});'
        f'node["barrier"="bollard"]({box});'
        ");out body;"
    )


def classify(tags: dict[str, object]) -> str | None:
    for (key, value), kind in KINDS.items():
        if tags.get(key) == value:
            return kind
    return None


def measure(raw: dict, runtime_slice: dict, radius_m: float) -> dict:
    origin = runtime_slice["origin"]
    anchors = [
        (float(item["x"]), float(item["z"]))
        for item in runtime_slice["corridor"]["anchors"]
    ]
    counts: Counter[str] = Counter()
    selected = []
    for element in raw.get("elements", []):
        if element.get("type") != "node":
            continue
        kind = classify(element.get("tags", {}) or {})
        if not kind or "lat" not in element or "lon" not in element:
            continue
        position = metric_point(
            float(element["lat"]), float(element["lon"]),
            float(origin["lat"]), float(origin["lon"]),
        )
        distance = corridor_distance((float(position[0]), float(position[1])), anchors)
        if distance <= radius_m:
            counts[kind] += 1
            selected.append({"osm_id": int(element["id"]), "kind": kind, "position": position, "corridor_distance_m": round(distance, 3)})
    ordered = {kind: counts.get(kind, 0) for kind in ("tree", "street_lamp", "bollard")}
    winner = max(ordered, key=ordered.get) if any(ordered.values()) else None
    ties = [kind for kind, count in ordered.items() if count == ordered.get(winner, -1)] if winner else []
    return {
        "format": "grand-bruxelles-osm-environment-coverage-v1",
        "source": "OpenStreetMap contributors via Overpass API",
        "license": "ODbL-1.0",
        "radius_m": radius_m,
        "counts": ordered,
        "total": sum(ordered.values()),
        "winner": winner if len(ties) == 1 else None,
        "tie": ties if len(ties) > 1 else [],
        "points": sorted(selected, key=lambda item: (item["kind"], item["osm_id"])),
    }


def fetch_live(query: str) -> dict:
    payload = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(OVERPASS_URL, data=payload, headers={"User-Agent": USER_AGENT, "Accept": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=100) as response:
        return json.load(response)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-slice", type=Path, default=Path("grand-bruxelles-game/data/osm/vertical_slice_01.game.json"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--radius-m", type=float, default=130.0)
    args = parser.parse_args()
    runtime_slice = json.loads(args.runtime_slice.read_text(encoding="utf-8"))
    result = measure(fetch_live(build_point_query(DEFAULT_BBOX)), runtime_slice, args.radius_m)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    print("OSM_ENVIRONMENT_COVERAGE", json.dumps({k: result[k] for k in ("counts", "total", "winner", "tie")}, sort_keys=True))
    if result["total"] == 0:
        raise SystemExit("no supported OSM environment points found in playable corridor")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
