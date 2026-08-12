#!/usr/bin/env python3
"""Extract the exact official Place de la Bourse StreetSurface polygons.

This tool is evidence/data preparation only. It never grants runtime approval.
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
WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
LAYER = "urbisvector:StreetSurfaces"
CRS = "EPSG:31370"
BOURSE_CENTER = (148620.23351135076, 170829.88213200308)
RADIUS_M = 180.0
TARGET_IDS = {
    "https://databrussels.be/id/streetsurface/22358",
    "https://databrussels.be/id/streetsurface/151495",
    "https://databrussels.be/id/streetsurface/152281",
}
AXIS_EVIDENCE = ROOT / "data" / "urbis" / "bourse_street_axes.game.json"


def probe_bbox() -> tuple[float, float, float, float]:
    east, north = BOURSE_CENTER
    return east - RADIUS_M, north - RADIUS_M, east + RADIUS_M, north + RADIUS_M


def load_world_transform(path: Path = AXIS_EVIDENCE) -> tuple[float, float, float, float]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    evidence = payload["world_coordinate_evidence"]
    lambert_e, lambert_n = (float(v) for v in evidence["lambert72_origin"])
    world_x, world_z = (float(v) for v in evidence["world_origin_xz"])
    return lambert_e, lambert_n, world_x, world_z


def transform_source_label(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT.resolve()))
    except ValueError:
        return str(path)


def to_world_xz(east: float, north: float, transform: tuple[float, float, float, float]) -> list[float]:
    lambert_e, lambert_n, world_x, world_z = transform
    return [east - lambert_e + world_x, -(north - lambert_n) + world_z]


def _polygon_rings(geometry: Any) -> list[list[list[float]]]:
    if not isinstance(geometry, dict) or geometry.get("type") != "Polygon":
        raise ValueError("target StreetSurface must be a Polygon")
    rings = geometry.get("coordinates")
    if not isinstance(rings, list) or not rings:
        raise ValueError("target StreetSurface polygon has no rings")
    normalized: list[list[list[float]]] = []
    for ring in rings:
        if not isinstance(ring, list) or len(ring) < 4:
            raise ValueError("StreetSurface ring must contain at least four coordinates")
        parsed: list[list[float]] = []
        for point in ring:
            if not isinstance(point, list) or len(point) < 2:
                raise ValueError("StreetSurface coordinate must contain E/N")
            parsed.append([float(point[0]), float(point[1])])
        if parsed[0] != parsed[-1]:
            raise ValueError("StreetSurface ring must be closed")
        normalized.append(parsed)
    return normalized


def extract_target_surfaces(payload: dict[str, Any], transform: tuple[float, float, float, float]) -> list[dict[str, Any]]:
    if payload.get("type") != "FeatureCollection":
        raise ValueError("expected FeatureCollection")
    found: dict[str, dict[str, Any]] = {}
    for feature in payload.get("features", []):
        if not isinstance(feature, dict):
            continue
        properties = feature.get("properties")
        if not isinstance(properties, dict):
            continue
        inspire_id = str(properties.get("INSPIRE_ID", ""))
        if inspire_id not in TARGET_IDS:
            continue
        if inspire_id in found:
            raise ValueError(f"duplicate target StreetSurface {inspire_id}")
        if properties.get("STRNAMEFRE") != "Place de la Bourse" or properties.get("STRNAMEDUT") != "Beursplein":
            raise ValueError(f"target StreetSurface has unexpected street identity: {inspire_id}")
        source_rings = _polygon_rings(feature.get("geometry"))
        world_rings = [
            [to_world_xz(point[0], point[1], transform) for point in ring]
            for ring in source_rings
        ]
        found[inspire_id] = {
            "inspire_id": inspire_id,
            "type_uninterpreted": properties.get("TYPE"),
            "area_m2": properties.get("AREA"),
            "level": properties.get("LVL"),
            "street_name_fr": properties.get("STRNAMEFRE"),
            "street_name_nl": properties.get("STRNAMEDUT"),
            "source_rings_epsg31370": source_rings,
            "world_rings_xz": world_rings,
        }
    missing = sorted(TARGET_IDS - set(found))
    if missing:
        raise RuntimeError(f"missing official Bourse StreetSurfaces: {missing}")
    return [found[inspire_id] for inspire_id in sorted(found)]


def fetch_live(timeout_s: int = 90) -> tuple[dict[str, Any], str]:
    min_e, min_n, max_e, max_n = probe_bbox()
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": LAYER,
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
    return json.loads(raw.decode("utf-8")), hashlib.sha256(raw).hexdigest()


def build_output(payload: dict[str, Any], response_sha256: str, transform_path: Path = AXIS_EVIDENCE) -> dict[str, Any]:
    transform = load_world_transform(transform_path)
    surfaces = extract_target_surfaces(payload, transform)
    return {
        "schema": "grand-bruxelles-urbis-bourse-surfaces-v1",
        "source": {
            "provider": "Paradigm / Brussels-Capital Region",
            "service": "UrbIS WFS",
            "url": WFS_URL,
            "layer": LAYER,
            "crs": CRS,
            "response_sha256": response_sha256,
            "response_hash_note": "raw WFS response hash is request evidence only; ephemeral feature IDs/order may change",
        },
        "target": "Place de la Bourse / Beursplein",
        "target_inspire_ids": sorted(TARGET_IDS),
        "world_coordinate_evidence": {
            "transform_source": transform_source_label(transform_path),
            "lambert72_origin": [transform[0], transform[1]],
            "world_origin_xz": [transform[2], transform[3]],
        },
        "surfaces": surfaces,
        "runtime_approved": False,
        "realism_complete": False,
        "next_runtime_step": "consume these exact polygons as bounded visual ground context, then rerender the fixed Bourse photo-match camera",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    payload, digest = fetch_live()
    output = build_output(payload, digest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({
        "surface_count": len(output["surfaces"]),
        "target_inspire_ids": output["target_inspire_ids"],
        "runtime_approved": output["runtime_approved"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
