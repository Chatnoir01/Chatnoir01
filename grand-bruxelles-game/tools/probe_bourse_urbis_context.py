#!/usr/bin/env python3
"""Probe official UrbIS context around Place de la Bourse without changing runtime data."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
CRS = "EPSG:31370"
BOURSE_WGS84 = (50.84787, 4.34916)
# EPSG:31370 conversion of the existing Bourse control point in vertical_slice_control_points.json.
BOURSE_CENTER = (148620.23351135076, 170829.88213200308)
RADIUS_M = 180.0
LAYERS = {
    "buildings": "urbisvector:Buildings",
    "street_surfaces": "urbisvector:StreetSurfaces",
    "street_axes": "urbisvector:StreetAxes",
}


def probe_bbox(center: tuple[float, float] = BOURSE_CENTER, radius_m: float = RADIUS_M) -> tuple[float, float, float, float]:
    east, north = center
    return east - radius_m, north - radius_m, east + radius_m, north + radius_m


def iter_xy(value: Any) -> Iterable[tuple[float, float]]:
    if not isinstance(value, list):
        return
    if len(value) >= 2 and all(isinstance(item, (int, float)) for item in value[:2]):
        yield float(value[0]), float(value[1])
        return
    for child in value:
        yield from iter_xy(child)


def summarize_geojson(data: dict[str, Any], center: tuple[float, float] = BOURSE_CENTER) -> dict[str, Any]:
    if data.get("type") != "FeatureCollection":
        raise ValueError(f"expected FeatureCollection, got {data.get('type')!r}")
    features = data.get("features", [])
    if not isinstance(features, list):
        raise ValueError("features must be a list")

    geometry_types: Counter[str] = Counter()
    coords: list[tuple[float, float]] = []
    for feature in features:
        geometry = feature.get("geometry") if isinstance(feature, dict) else None
        if not isinstance(geometry, dict):
            continue
        geometry_types[str(geometry.get("type", "unknown"))] += 1
        coords.extend(iter_xy(geometry.get("coordinates")))

    if features and not coords:
        raise ValueError("features contain no numeric EPSG:31370 coordinates")

    bounds = None
    nearest_m = None
    if coords:
        xs = [point[0] for point in coords]
        ys = [point[1] for point in coords]
        bounds = [min(xs), min(ys), max(xs), max(ys)]
        nearest_m = min(math.hypot(x - center[0], y - center[1]) for x, y in coords)

    return {
        "features": len(features),
        "geometry_types": dict(sorted(geometry_types.items())),
        "coordinate_count": len(coords),
        "coordinate_bounds": bounds,
        "nearest_coordinate_to_bourse_m": nearest_m,
    }


def fetch_layer(layer_name: str, bbox: tuple[float, float, float, float], timeout_s: int = 90) -> tuple[dict[str, Any], str]:
    min_e, min_n, max_e, max_n = bbox
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": layer_name,
        "outputFormat": "application/json",
        "srsName": CRS,
        "bbox": f"{min_e},{min_n},{max_e},{max_n},{CRS}",
    }
    request = urllib.request.Request(
        WFS_URL + "?" + urllib.parse.urlencode(params),
        headers={
            "User-Agent": "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
            "Accept": "application/geo+json, application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout_s) as response:
        raw = response.read()
    payload = json.loads(raw.decode("utf-8"))
    return payload, hashlib.sha256(raw).hexdigest()


def build_report() -> dict[str, Any]:
    bbox = probe_bbox()
    report: dict[str, Any] = {
        "schema": "grand-bruxelles-bourse-urbis-context-probe-v1",
        "source": WFS_URL,
        "crs": CRS,
        "license_provenance": "official UrbIS/Paradigm WFS; evidence probe only, no runtime approval implied",
        "bourse_control_point": {
            "wgs84_lat_lon": list(BOURSE_WGS84),
            "epsg31370_east_north": list(BOURSE_CENTER),
            "source_file": "data/vertical_slice_control_points.json",
        },
        "radius_m": RADIUS_M,
        "bbox": list(bbox),
        "layers": {},
        "runtime_approved": False,
    }
    for short_name, layer_name in LAYERS.items():
        payload, digest = fetch_layer(layer_name, bbox)
        summary = summarize_geojson(payload)
        if summary["features"] <= 0:
            raise RuntimeError(f"official UrbIS layer {layer_name} returned zero features in Bourse probe bbox")
        report["layers"][short_name] = {
            "wfs_name": layer_name,
            "response_sha256": digest,
            **summary,
        }
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = build_report()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
