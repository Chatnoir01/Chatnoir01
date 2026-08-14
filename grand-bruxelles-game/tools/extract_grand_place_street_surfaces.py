#!/usr/bin/env python3
"""Extract a bounded official UrbIS StreetSurface evidence slice around Grand-Place.

Evidence only. The output never grants runtime approval and never invents curb height,
paving material, landmark dimensions, or semantic TYPE meaning.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
LAYER = "urbisvector:StreetSurfaces"
CRS = "EPSG:31370"
LICENSE = "CC0-1.0"
DATASET_URL = "https://datastore.brussels/web/data/dataset/af847c40-848b-11ee-9a1f-00090ffe0001"

# Exact world transform already locked by the Bourse StreetSurface runtime.
LAMBERT72_ORIGIN = (147868.29422791934, 169538.62414926197)
WORLD_ORIGIN_XZ = (-668.5, 627.84)
GRAND_PLACE_GAME_XZ = (319.01, -535.2)
HALF_SIZE_M = 95.0


def _game_to_lambert(x: float, z: float) -> tuple[float, float]:
    return (
        LAMBERT72_ORIGIN[0] + (x - WORLD_ORIGIN_XZ[0]),
        LAMBERT72_ORIGIN[1] + (WORLD_ORIGIN_XZ[1] - z),
    )


def _target_bbox() -> tuple[float, float, float, float]:
    x, y = _game_to_lambert(*GRAND_PLACE_GAME_XZ)
    return x - HALF_SIZE_M, y - HALF_SIZE_M, x + HALF_SIZE_M, y + HALF_SIZE_M


def _geometry_rings(geometry: Any) -> list[list[list[float]]]:
    if not isinstance(geometry, dict):
        return []
    gtype = geometry.get("type")
    coords = geometry.get("coordinates")
    polygons: list[Any]
    if gtype == "Polygon":
        polygons = [coords]
    elif gtype == "MultiPolygon":
        polygons = list(coords or [])
    else:
        return []
    result: list[list[list[float]]] = []
    for polygon in polygons:
        if not isinstance(polygon, list) or not polygon:
            continue
        exterior = polygon[0]
        if not isinstance(exterior, list) or len(exterior) < 4:
            continue
        ring = [[float(p[0]), float(p[1])] for p in exterior if isinstance(p, list) and len(p) >= 2]
        if len(ring) >= 4 and ring[0] == ring[-1]:
            result.append(ring)
    return result


def _level(props: dict[str, Any]) -> int | None:
    for key in ("lvl", "LVL", "level", "LEVEL"):
        if key in props and props[key] is not None:
            try:
                return int(props[key])
            except (TypeError, ValueError):
                return None
    return None


def fetch_live(timeout_s: int = 90) -> tuple[dict[str, Any], str, str]:
    bbox = _target_bbox()
    params = {
        "service": "WFS",
        "version": "1.1.0",
        "request": "GetFeature",
        "typeName": LAYER,
        "outputFormat": "application/json",
        "srsName": CRS,
        "bbox": ",".join(str(v) for v in bbox) + "," + CRS,
    }
    url = WFS_URL + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"User-Agent": "Grand-Bruxelles-Game/grand-place-surface-evidence"})
    with urllib.request.urlopen(request, timeout=timeout_s) as response:
        raw = response.read()
    return json.loads(raw.decode("utf-8")), hashlib.sha256(raw).hexdigest(), url


def build_evidence(payload: dict[str, Any], digest: str, request_url: str) -> dict[str, Any]:
    if payload.get("type") != "FeatureCollection":
        raise ValueError("expected WFS FeatureCollection")
    features: list[dict[str, Any]] = []
    for feature in payload.get("features", []):
        if not isinstance(feature, dict):
            continue
        props = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
        rings = _geometry_rings(feature.get("geometry"))
        if not rings:
            continue
        features.append({
            "source_id": str(feature.get("id", "")),
            "level": _level(props),
            "properties": props,
            "source_rings_epsg31370": rings,
        })
    features.sort(key=lambda item: item["source_id"])
    return {
        "schema": "grand-bruxelles-grand-place-street-surface-evidence-v1",
        "source": {
            "provider": "Paradigm / Brussels-Capital Region",
            "dataset": "UrbIS - Transport networks",
            "dataset_url": DATASET_URL,
            "wfs": WFS_URL,
            "layer": LAYER,
            "crs": CRS,
            "license": LICENSE,
            "request_url": request_url,
            "response_sha256": digest,
        },
        "selection": {
            "basis": "fixed Grand-Place corridor anchor plus 95 m evidence-only halo",
            "grand_place_game_xz": list(GRAND_PLACE_GAME_XZ),
            "bbox_epsg31370": list(_target_bbox()),
            "feature_count": len(features),
            "level_zero_count": sum(1 for item in features if item["level"] == 0),
        },
        "features": features,
        "runtime_approved": False,
        "realism_complete": False,
        "curb_elevation_resolved": False,
        "notes": "Raw bounded StreetSurface evidence only. No feature is promoted until target identity and player-visible suitability are verified.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    payload, digest, request_url = fetch_live()
    evidence = build_evidence(payload, digest, request_url)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    print("Grand-Place StreetSurface evidence: %d features, %d level-0" % (
        evidence["selection"]["feature_count"], evidence["selection"]["level_zero_count"]
    ))
    print("BBOX EPSG:31370: %s" % evidence["selection"]["bbox_epsg31370"])
    print("Source SHA-256: %s" % digest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
