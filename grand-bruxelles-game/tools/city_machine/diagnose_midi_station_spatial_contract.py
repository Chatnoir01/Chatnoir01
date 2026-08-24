#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATION_ID = "BE.BRUSSELS.BRIC.TOPO.POINT.128052"


def ring_bounds(points):
    xs = [float(p[0]) for p in points]
    ys = [float(p[1]) for p in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def centroid(points):
    n = len(points)
    return [sum(float(p[0]) for p in points) / n, sum(float(p[1]) for p in points) / n]


def raw_rings(geometry):
    if not geometry:
        return []
    coords = geometry.get("coordinates", [])
    if geometry.get("type") == "Polygon":
        return [coords[0]] if coords else []
    if geometry.get("type") == "MultiPolygon":
        return [poly[0] for poly in coords if poly]
    return []


def main() -> int:
    manifest = json.loads((ROOT / "data/urbis/midi/manifest.json").read_text(encoding="utf-8"))
    raw = json.loads((ROOT / "data/urbis/midi/buildings.geojson").read_text(encoding="utf-8"))
    runtime = json.loads((ROOT / "data/urbis/midi/midi_runtime.game.json").read_text(encoding="utf-8"))
    controller_text = (ROOT / "game/scripts/player_controller.gd").read_text(encoding="utf-8")

    raw_matches = []
    for feature in raw.get("features", []):
        props = feature.get("properties") or {}
        fid = str(props.get("INSPIRE_ID") or feature.get("id") or "")
        if fid == STATION_ID:
            raw_matches.append(feature)

    runtime_matches = [b for b in runtime.get("buildings", []) if str(b.get("id", "")) == STATION_ID]

    origin = manifest["game_origin"]
    bbox = [float(v) for v in manifest["bbox"]]
    m = re.search(
        r"MIDI_FAST_TRAVEL_POSITION\s*:=\s*Vector3\(\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*\)",
        controller_text,
    )
    if not m:
        raise SystemExit("MIDI_FAST_TRAVEL_POSITION not found")
    fast = [float(m.group(1)), float(m.group(2)), float(m.group(3))]
    fast_lambert = [float(origin["e"]) + fast[0], float(origin["n"]) - fast[2]]
    fast_in_manifest_bbox = bbox[0] <= fast_lambert[0] <= bbox[2] and bbox[1] <= fast_lambert[1] <= bbox[3]

    raw_station = None
    if raw_matches:
        rings = raw_rings(raw_matches[0].get("geometry"))
        if rings:
            raw_station = {
                "lambert_bounds": ring_bounds(rings[0]),
                "lambert_centroid": centroid(rings[0]),
            }

    runtime_station = None
    if runtime_matches:
        footprint = runtime_matches[0].get("footprint", [])
        runtime_station = {
            "game_bounds": ring_bounds(footprint),
            "game_centroid": centroid(footprint),
        }

    result = {
        "schema": "grand-bruxelles-midi-station-spatial-diagnostic-v1",
        "station_id": STATION_ID,
        "raw_station_present": bool(raw_matches),
        "runtime_station_present": bool(runtime_matches),
        "raw_station": raw_station,
        "runtime_station": runtime_station,
        "runtime_radius_m": runtime.get("radius_m"),
        "manifest_bbox_lambert72": bbox,
        "fast_travel_game": fast,
        "fast_travel_lambert72": fast_lambert,
        "fast_travel_in_manifest_bbox": fast_in_manifest_bbox,
    }
    print(json.dumps(result, indent=2, sort_keys=True))

    if not raw_matches:
        print("MIDI_STATION_SPATIAL_FAIL raw authoritative station building missing")
        return 2
    print("MIDI_STATION_SPATIAL_DIAGNOSTIC_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
