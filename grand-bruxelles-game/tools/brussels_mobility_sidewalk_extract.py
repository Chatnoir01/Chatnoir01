#!/usr/bin/env python3
"""Bounded, fail-closed Brussels Mobility sidewalk extractor.

This tool only establishes source-backed horizontal sidewalk geometry and the
published SW semantic class. It never authorizes runtime geometry, elevations,
curb profiles, paving dimensions, or material identity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

SCHEMA = "grand-bruxelles-official-sidewalk-corridor-extract-v1"
CRS = "EPSG:31370"
LAYER = "bm_urbis:urbadm_ssw"
REQUIRED_CLASS = "SW"
DEFAULT_BBOX = [147650.0, 169300.0, 149100.0, 171050.0]
WFS_ENDPOINT = "https://data.mobility.brussels/geoserver/bm_urbis/wfs"
ALLOWED_GEOMETRIES = {"Polygon", "MultiPolygon"}


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _validate_bbox(query_bbox: list[float]) -> list[float]:
    if len(query_bbox) != 4:
        raise ValueError("query bbox must contain exactly four coordinates")
    bbox = [float(value) for value in query_bbox]
    min_x, min_y, max_x, max_y = bbox
    if not (min_x < max_x and min_y < max_y):
        raise ValueError("query bbox is not ordered")
    if bbox != DEFAULT_BBOX:
        raise ValueError(f"query bbox drifted from reviewed corridor scope: {bbox}")
    return bbox


def build_wfs_url(query_bbox: list[float] | None = None) -> str:
    bbox = _validate_bbox(query_bbox or DEFAULT_BBOX)
    params = {
        "service": "WFS",
        "version": "1.1.0",
        "request": "GetFeature",
        "typeName": LAYER,
        "outputFormat": "json",
        "srsName": CRS,
        "bbox": ",".join(f"{value:.3f}" for value in bbox),
    }
    return f"{WFS_ENDPOINT}?{urlencode(params)}"


def _canonical_geometry(feature: dict[str, Any]) -> dict[str, Any]:
    geometry = feature.get("geometry")
    if not isinstance(geometry, dict):
        raise ValueError("feature geometry missing")
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if geometry_type not in ALLOWED_GEOMETRIES:
        raise ValueError(f"unsupported sidewalk geometry type: {geometry_type}")
    if not isinstance(coordinates, list) or not coordinates:
        raise ValueError("sidewalk geometry coordinates missing")
    return {"type": geometry_type, "coordinates": coordinates}


def canonicalize_feature_collection(raw: bytes, query_bbox: list[float] | None = None) -> dict[str, Any]:
    bbox = _validate_bbox(query_bbox or DEFAULT_BBOX)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("official sidewalk response is not valid UTF-8 GeoJSON") from exc
    if not isinstance(payload, dict) or payload.get("type") != "FeatureCollection":
        raise ValueError("official sidewalk response is not a FeatureCollection")
    source_features = payload.get("features")
    if not isinstance(source_features, list) or not source_features:
        raise ValueError("official sidewalk response has no features")

    features: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for feature in source_features:
        if not isinstance(feature, dict):
            raise ValueError("malformed sidewalk feature")
        feature_id = str(feature.get("id", "")).strip()
        if not feature_id:
            raise ValueError("sidewalk feature identity missing")
        if feature_id in seen_ids:
            raise ValueError(f"duplicate sidewalk feature identity: {feature_id}")
        seen_ids.add(feature_id)
        properties = feature.get("properties")
        if not isinstance(properties, dict):
            raise ValueError(f"sidewalk feature properties missing: {feature_id}")
        ssft = str(properties.get("ssft", "")).strip()
        if ssft != REQUIRED_CLASS:
            raise ValueError(f"non-SW feature leaked into sidewalk extract: {feature_id} ssft={ssft!r}")
        features.append({"feature_id": feature_id, "ssft": ssft, "geometry": _canonical_geometry(feature)})

    features.sort(key=lambda item: item["feature_id"])
    ids_bytes = "".join(f"{item['feature_id']}\n" for item in features).encode("utf-8")
    return {
        "schema": SCHEMA,
        "source": {
            "publisher": "Paradigm",
            "dataset": "Trottoir",
            "layer": LAYER,
            "license": "CC0-1.0",
            "crs": CRS,
            "semantic_field": "ssft",
            "semantic_class": REQUIRED_CLASS,
            "wfs_endpoint": WFS_ENDPOINT,
        },
        "crs": CRS,
        "query_bbox": bbox,
        "query_filter": "bounded layer query; canonicalizer requires ssft='SW' for every feature",
        "feature_count": len(features),
        "source_sha256": _sha256(raw),
        "feature_id_sha256": _sha256(ids_bytes),
        "features": features,
        "claims": {
            "horizontal_sidewalk_geometry_source_backed": True,
            "sidewalk_semantic_class_source_backed": True,
            "curb_height_source_backed": False,
            "surface_elevation_source_backed": False,
            "sidewalk_profile_source_backed": False,
            "paving_unit_dimensions_source_backed": False,
            "material_identity_source_backed": False,
        },
        "policy": {
            "runtime_geometry_authorized": False,
            "jouable_promotion_authorized": False,
            "vertical_extrusion_allowed": False,
            "curb_height_inference_allowed": False,
            "game_world_transform_applied": False,
            "source_geometry_modified": False,
        },
    }


def fetch_official(query_bbox: list[float] | None = None, timeout_seconds: int = 90) -> tuple[bytes, str]:
    url = build_wfs_url(query_bbox)
    request = Request(url, headers={"Accept": "application/json", "User-Agent": "Grand-Bruxelles-Source-Gate/1.0"})
    with urlopen(request, timeout=timeout_seconds) as response:
        content_type = str(response.headers.get("Content-Type", ""))
        raw = response.read()
    if "json" not in content_type.lower() and not raw.lstrip().startswith(b"{"):
        snippet = raw[:500].decode("utf-8", errors="replace").replace("\n", " ")
        raise ValueError(f"official sidewalk WFS returned non-JSON content: {content_type}; {snippet}")
    return raw, url


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, help="Read a captured WFS GeoJSON response instead of the network")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--raw-output", type=Path, help="Persist exact source bytes when network acquisition is used")
    parser.add_argument("--bbox", nargs=4, type=float, default=DEFAULT_BBOX)
    args = parser.parse_args()

    bbox = _validate_bbox(list(args.bbox))
    if args.input:
        raw = args.input.read_bytes()
        source_url = "fixture-or-captured-source"
    else:
        raw, source_url = fetch_official(bbox)
        if args.raw_output:
            args.raw_output.parent.mkdir(parents=True, exist_ok=True)
            args.raw_output.write_bytes(raw)

    canonical = canonicalize_feature_collection(raw, query_bbox=bbox)
    canonical["source_query_url"] = source_url
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(canonical, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        "OFFICIAL_SIDEWALK_EXTRACT_OK "
        f"features={canonical['feature_count']} "
        f"source_sha256={canonical['source_sha256']} "
        f"feature_id_sha256={canonical['feature_id_sha256']} "
        f"bbox={','.join(str(value) for value in bbox)} "
        f"runtime_authorized={canonical['policy']['runtime_geometry_authorized']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
