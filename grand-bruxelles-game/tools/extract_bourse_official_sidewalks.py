#!/usr/bin/env python3
"""Extract a tightly bounded official Brussels Mobility/UrbIS sidewalk slice around Bourse.

Evidence preparation only: this tool never grants runtime approval or invents curb height.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
WFS_URL = "https://data.mobility.brussels/geoserver/bm_urbis/wfs"
LAYER = "bm_urbis:urbadm_ssw"
CRS = "EPSG:31370"
LICENSE = "CC0-1.0"
SOURCE_PAGE = "https://data.mobility.brussels/en/info/urbadm_ssw/"
PAD_M = 8.0
SURFACE_FILES = (
    "data/urbis/bourse_street_surfaces.game.json",
    "data/urbis/bourse_street_surfaces_adjacent_22982.game.json",
    "data/urbis/bourse_street_surfaces_adjacent_41098.game.json",
    "data/urbis/bourse_street_surfaces_adjacent_41084.game.json",
    "data/urbis/bourse_street_surfaces_adjacent_21944.game.json",
)


def _surface_bbox(root: Path = ROOT) -> tuple[float, float, float, float]:
    xs: list[float] = []
    ys: list[float] = []
    for rel in SURFACE_FILES:
        payload = json.loads((root / rel).read_text(encoding="utf-8"))
        for surface in payload.get("surfaces", []):
            if int(surface.get("level", 999)) != 0:
                continue
            for ring in surface.get("source_rings_epsg31370", []):
                for point in ring:
                    xs.append(float(point[0]))
                    ys.append(float(point[1]))
    if not xs:
        raise RuntimeError("no current Bourse source rings found")
    return min(xs) - PAD_M, min(ys) - PAD_M, max(xs) + PAD_M, max(ys) + PAD_M


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


def _ring_bbox(ring: list[list[float]]) -> tuple[float, float, float, float]:
    return min(p[0] for p in ring), min(p[1] for p in ring), max(p[0] for p in ring), max(p[1] for p in ring)


def _intersects(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return not (a[2] < b[0] or a[0] > b[2] or a[3] < b[1] or a[1] > b[3])


def extract_features(payload: dict[str, Any], target_bbox: tuple[float, float, float, float]) -> list[dict[str, Any]]:
    if payload.get("type") != "FeatureCollection":
        raise ValueError("expected FeatureCollection")
    out: list[dict[str, Any]] = []
    for feature in payload.get("features", []):
        if not isinstance(feature, dict):
            continue
        rings = [ring for ring in _geometry_rings(feature.get("geometry")) if _intersects(_ring_bbox(ring), target_bbox)]
        if not rings:
            continue
        props = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
        out.append({
            "source_id": str(feature.get("id", props.get("id", ""))),
            "ssft": props.get("ssft"),
            "properties": props,
            "source_rings_epsg31370": rings,
        })
    out.sort(key=lambda item: (item["source_id"], json.dumps(item["source_rings_epsg31370"], sort_keys=True)))
    return out


def fetch_live(target_bbox: tuple[float, float, float, float], timeout_s: int = 90) -> tuple[dict[str, Any], str]:
    params = {
        "service": "wfs",
        "version": "1.1.0",
        "request": "GetFeature",
        "typeName": LAYER,
        "outputFormat": "json",
        "srsName": CRS,
        "bbox": ",".join(str(v) for v in target_bbox) + "," + CRS,
    }
    url = WFS_URL + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "Grand-Bruxelles-Game/sidewalk-evidence"})
    with urllib.request.urlopen(req, timeout=timeout_s) as response:
        raw = response.read()
    return json.loads(raw.decode("utf-8")), hashlib.sha256(raw).hexdigest()


def build_evidence(payload: dict[str, Any], source_sha256: str, root: Path = ROOT) -> dict[str, Any]:
    bbox = _surface_bbox(root)
    features = extract_features(payload, bbox)
    if not features:
        raise RuntimeError("official sidewalk query returned no bounded Bourse features")
    return {
        "schema": "grand-bruxelles-bourse-official-sidewalk-evidence-v1",
        "source": {
            "publisher": "Brussels Mobility / Paradigm",
            "source_page": SOURCE_PAGE,
            "wfs": WFS_URL,
            "layer": LAYER,
            "crs": CRS,
            "license": LICENSE,
            "response_sha256": source_sha256,
        },
        "selection": {
            "basis": "current seven official Bourse StreetSurfaces plus 8 m bounded halo",
            "bbox_epsg31370": list(bbox),
            "feature_count": len(features),
        },
        "features": features,
        "runtime_approved": False,
        "realism_complete": False,
        "curb_elevation_resolved": False,
        "notes": "Official sidewalk geometry only. No curb height, pavement material, or semantic inference is introduced.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    bbox = _surface_bbox()
    payload, digest = fetch_live(bbox)
    evidence = build_evidence(payload, digest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Bourse official sidewalks: {evidence['selection']['feature_count']} features")
    print(f"BBOX EPSG:31370: {evidence['selection']['bbox_epsg31370']}")
    print(f"Source SHA-256: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
