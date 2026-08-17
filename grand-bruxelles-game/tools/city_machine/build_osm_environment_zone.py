#!/usr/bin/env python3
"""Build a deterministic zone OSM environment cache/runtime artifact.

Live Overpass refresh is explicit. Nominal city-machine builds consume the
committed normalized cache so they stay reproducible and network-independent.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

try:
    from pyproj import Transformer
except ImportError as exc:  # fail closed: an approximate CRS transform is not acceptable
    raise SystemExit("pyproj is required: pip install 'pyproj>=3.7,<4'") from exc

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from fetch_osm_slice import fetch
from make_runtime_slice import selected_bounds
from measure_osm_environment_coverage import build_point_query
from transform_osm_to_game import environment_point_kind

SUPPORTED_KINDS = ("tree", "street_lamp", "bollard")
SOURCE = "OpenStreetMap contributors via Overpass API"
LICENSE = "ODbL-1.0"


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def digest(value: dict[str, Any]) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def bbox_wgs84(manifest: dict[str, Any]) -> list[float]:
    if manifest.get("source_crs") != "EPSG:31370":
        raise ValueError("zone manifest must use EPSG:31370")
    bbox = manifest.get("bbox")
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise ValueError("zone manifest bbox must be [minE,minN,maxE,maxN]")
    min_e, min_n, max_e, max_n = map(float, bbox)
    if min_e >= max_e or min_n >= max_n:
        raise ValueError("invalid EPSG:31370 bbox")
    to_wgs84 = Transformer.from_crs("EPSG:31370", "EPSG:4326", always_xy=True)
    corners = [
        to_wgs84.transform(e, n)
        for e in (min_e, max_e)
        for n in (min_n, max_n)
    ]
    lons = [float(lon) for lon, _ in corners]
    lats = [float(lat) for _, lat in corners]
    return [min(lats), min(lons), max(lats), max(lons)]


def normalize_overpass(raw: dict[str, Any], bbox: list[float]) -> dict[str, Any]:
    elements: list[dict[str, Any]] = []
    for element in raw.get("elements", []) or []:
        if element.get("type") != "node" or "lat" not in element or "lon" not in element:
            continue
        tags = element.get("tags") or {}
        kind = environment_point_kind(tags)
        if kind not in SUPPORTED_KINDS:
            continue
        keep_tags: dict[str, str] = {}
        for key in ("natural", "highway", "barrier"):
            if key in tags:
                keep_tags[key] = str(tags[key])
        elements.append({
            "id": int(element["id"]),
            "lat": round(float(element["lat"]), 8),
            "lon": round(float(element["lon"]), 8),
            "tags": keep_tags,
        })
    elements.sort(key=lambda item: (environment_point_kind(item["tags"]) or "", item["id"]))
    counts = Counter(environment_point_kind(item["tags"]) for item in elements)
    return {
        "format": "grand-bruxelles-osm-zone-environment-cache-v1",
        "source": SOURCE,
        "license": LICENSE,
        "bbox_wgs84": [round(float(value), 8) for value in bbox],
        "osm_base_timestamp": str((raw.get("osm3s") or {}).get("timestamp_osm_base") or ""),
        "counts": {kind: int(counts.get(kind, 0)) for kind in SUPPORTED_KINDS},
        "elements": elements,
    }


def project_cache(cache: dict[str, Any], manifest: dict[str, Any], zone_id: str) -> dict[str, Any]:
    if cache.get("format") != "grand-bruxelles-osm-zone-environment-cache-v1":
        raise ValueError("unsupported OSM environment cache format")
    if cache.get("source") != SOURCE or cache.get("license") != LICENSE:
        raise ValueError("OSM source/license contract mismatch")
    origin = manifest.get("game_origin") or {}
    if origin.get("axes") != "X=east, Y=up, Z=south" or origin.get("units") != "metres":
        raise ValueError("unsupported game-origin contract")
    origin_e = float(origin["e"])
    origin_n = float(origin["n"])
    to_lambert72 = Transformer.from_crs("EPSG:4326", "EPSG:31370", always_xy=True)
    points: list[dict[str, Any]] = []
    counts: Counter[str] = Counter()
    for element in cache.get("elements", []) or []:
        kind = environment_point_kind(element.get("tags") or {})
        if kind not in SUPPORTED_KINDS:
            continue
        e, n = to_lambert72.transform(float(element["lon"]), float(element["lat"]))
        points.append({
            "osm_id": int(element["id"]),
            "kind": kind,
            "position": [round(float(e) - origin_e, 3), round(-(float(n) - origin_n), 3)],
        })
        counts[kind] += 1
    points.sort(key=lambda item: (item["kind"], item["osm_id"]))
    stats = {kind: int(counts.get(kind, 0)) for kind in SUPPORTED_KINDS}
    stats["total"] = len(points)
    return {
        "format": "grand-bruxelles-osm-zone-environment-v1",
        "zone": zone_id,
        "source": SOURCE,
        "license": LICENSE,
        "source_crs": "EPSG:4326",
        "projection_crs": "EPSG:31370",
        "bbox_31370": [float(value) for value in manifest["bbox"]],
        "bbox_wgs84": cache["bbox_wgs84"],
        "game_origin": origin,
        "source_digest": digest(cache),
        "osm_base_timestamp": cache.get("osm_base_timestamp", ""),
        "stats": stats,
        "bounds_m": selected_bounds(points),
        "environment_points": points,
    }


def refresh_cache(manifest: dict[str, Any]) -> dict[str, Any]:
    bbox = bbox_wgs84(manifest)
    raw = fetch(build_point_query(tuple(bbox)))
    cache = normalize_overpass(raw, bbox)
    if not cache["elements"]:
        raise RuntimeError("Overpass returned no supported environment points")
    return cache


def build(manifest_path: Path, zone_id: str, cache_path: Path, output_path: Path, refresh: bool) -> dict[str, Any]:
    manifest = read_json(manifest_path)
    if refresh:
        cache = refresh_cache(manifest)
        write_json(cache_path, cache)
    else:
        if not cache_path.is_file():
            raise FileNotFoundError(f"OSM environment cache missing: {cache_path}")
        cache = read_json(cache_path)
    result = project_cache(cache, manifest, zone_id)
    if int(result["stats"]["tree"]) <= 0:
        raise RuntimeError("OSM environment source has zero trees")
    write_json(output_path, result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Build exact zone-aligned OSM environment points")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--zone", required=True)
    parser.add_argument("--raw-cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--refresh", action="store_true", help="explicitly refresh the normalized Overpass cache")
    args = parser.parse_args()
    result = build(args.manifest, args.zone, args.raw_cache, args.output, args.refresh)
    print(f"OSM_ZONE_ENVIRONMENT_OK zone={args.zone} stats={result['stats']} bounds={result['bounds_m']} source_digest={result['source_digest']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
