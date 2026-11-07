#!/usr/bin/env python3
"""Fetch a compact UrbIS WFS extract for Grand Bruxelles.

The script requests official UrbIS vector layers directly from Paradigm's WFS,
using Belgian Lambert 72 (EPSG:31370). It is intentionally bbox-based so each
city zone can be refreshed independently and kept small enough for CI/game use.

Large/temporarily slow WFS responses are handled conservatively: after bounded
retries on the exact requested bbox, the fetcher subdivides that same Lambert 72
bbox into four exact quadrants, requests each quadrant independently, and merges
the FeatureCollections with deterministic feature de-duplication. This changes
only transport strategy, never the geographic area or authoritative source.
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
DEFAULT_BBOX = (147250.0, 168900.0, 148500.0, 170250.0)
DEFAULT_LAYERS = {
    "buildings": "urbisvector:Buildings",
    "street_surfaces": "urbisvector:StreetSurfaces",
    "street_axes": "urbisvector:StreetAxes",
    "tram_network": "urbisvector:TramNetwork",
    "train_network": "urbisvector:TrainNetwork",
}
REQUEST_TIMEOUT_SECONDS = 90
DIRECT_RETRIES_BEFORE_SUBDIVISION = 2
MIN_SUBDIVISION_SPAN_METERS = 125.0


def parse_bbox(raw: str) -> tuple[float, float, float, float]:
    parts = [float(part.strip()) for part in raw.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("bbox must be minE,minN,maxE,maxN")
    min_e, min_n, max_e, max_n = parts
    if min_e >= max_e or min_n >= max_n:
        raise argparse.ArgumentTypeError("invalid bbox extent")
    return min_e, min_n, max_e, max_n


def _build_request(layer_name: str, bbox: tuple[float, float, float, float]) -> urllib.request.Request:
    min_e, min_n, max_e, max_n = bbox
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": layer_name,
        "outputFormat": "application/json",
        "srsName": "EPSG:31370",
        "bbox": f"{min_e},{min_n},{max_e},{max_n},EPSG:31370",
    }
    url = WFS_URL + "?" + urllib.parse.urlencode(params)
    return urllib.request.Request(
        url,
        headers={
            "User-Agent": "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
            "Accept": "application/geo+json, application/json",
        },
    )


def _request_with_retries(
    layer_name: str,
    bbox: tuple[float, float, float, float],
    retries: int,
) -> dict[str, Any]:
    request = _build_request(layer_name, bbox)
    last_error: Exception | None = None
    attempts = max(1, retries)
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                payload = response.read()
            data = json.loads(payload.decode("utf-8"))
            if data.get("type") != "FeatureCollection":
                raise RuntimeError(f"unexpected WFS payload for {layer_name}: {data.get('type')!r}")
            return data
        except Exception as exc:  # network/service failures are retriable in CI
            last_error = exc
            if attempt >= attempts:
                break
            time.sleep(min(12, 2 ** attempt))
    raise RuntimeError(f"failed to fetch {layer_name} after {attempts} attempts: {last_error}")


def _subdivide_bbox(
    bbox: tuple[float, float, float, float],
) -> tuple[tuple[float, float, float, float], ...]:
    min_e, min_n, max_e, max_n = bbox
    mid_e = (min_e + max_e) / 2.0
    mid_n = (min_n + max_n) / 2.0
    return (
        (min_e, min_n, mid_e, mid_n),
        (mid_e, min_n, max_e, mid_n),
        (min_e, mid_n, mid_e, max_n),
        (mid_e, mid_n, max_e, max_n),
    )


def _feature_key(feature: dict[str, Any]) -> str:
    feature_id = feature.get("id")
    if feature_id not in (None, ""):
        return f"id:{feature_id}"
    stable_payload = {
        "geometry": feature.get("geometry"),
        "properties": feature.get("properties"),
    }
    return "content:" + json.dumps(stable_payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _merge_feature_collections(
    layer_name: str,
    bbox: tuple[float, float, float, float],
    documents: list[dict[str, Any]],
) -> dict[str, Any]:
    if not documents:
        raise RuntimeError(f"cannot merge empty WFS subdivision for {layer_name}")

    merged = {key: value for key, value in documents[0].items() if key != "features"}
    features: list[dict[str, Any]] = []
    seen: set[str] = set()
    duplicate_count = 0
    for document in documents:
        if document.get("type") != "FeatureCollection":
            raise RuntimeError(f"unexpected subdivided WFS payload for {layer_name}: {document.get('type')!r}")
        for feature in document.get("features", []):
            key = _feature_key(feature)
            if key in seen:
                duplicate_count += 1
                continue
            seen.add(key)
            features.append(feature)

    merged["type"] = "FeatureCollection"
    merged["features"] = features
    merged["numberReturned"] = len(features)
    merged["grand_bruxelles_fetch"] = {
        "strategy": "adaptive_quadrant_subdivision",
        "layer": layer_name,
        "bbox": list(bbox),
        "parts": len(documents),
        "deduplicated_features": duplicate_count,
    }
    return merged


def request_layer(layer_name: str, bbox: tuple[float, float, float, float], retries: int) -> dict:
    attempts = max(1, retries)
    direct_attempts = min(attempts, DIRECT_RETRIES_BEFORE_SUBDIVISION)
    try:
        data = _request_with_retries(layer_name, bbox, direct_attempts)
        data["grand_bruxelles_fetch"] = {
            "strategy": "direct_bbox",
            "layer": layer_name,
            "bbox": list(bbox),
            "attempt_budget": direct_attempts,
        }
        return data
    except RuntimeError as direct_error:
        min_e, min_n, max_e, max_n = bbox
        if min(max_e - min_e, max_n - min_n) < MIN_SUBDIVISION_SPAN_METERS:
            raise direct_error

        quadrant_documents: list[dict[str, Any]] = []
        quadrant_errors: list[str] = []
        for quadrant in _subdivide_bbox(bbox):
            try:
                quadrant_documents.append(_request_with_retries(layer_name, quadrant, attempts))
            except RuntimeError as exc:
                quadrant_errors.append(str(exc))
                break
        if quadrant_errors:
            raise RuntimeError(
                f"failed to fetch {layer_name} directly and via exact quadrant subdivision: "
                f"direct={direct_error}; subdivision={quadrant_errors[-1]}"
            ) from direct_error
        return _merge_feature_collections(layer_name, bbox, quadrant_documents)


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch official UrbIS WFS geometry for a game zone")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--bbox", type=parse_bbox, default=DEFAULT_BBOX)
    parser.add_argument("--retries", type=int, default=4)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "format": "grand-bruxelles-urbis-wfs-v1",
        "source": WFS_URL,
        "crs": "EPSG:31370",
        "bbox": list(args.bbox),
        "layers": {},
    }

    for short_name, layer_name in DEFAULT_LAYERS.items():
        data = request_layer(layer_name, args.bbox, max(1, args.retries))
        path = args.output_dir / f"{short_name}.geojson"
        path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        count = len(data.get("features", []))
        manifest["layers"][short_name] = {
            "wfs_name": layer_name,
            "features": count,
            "file": path.name,
            "fetch": data.get("grand_bruxelles_fetch"),
        }
        print(f"{short_name}: {count} features -> {path}")

    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"manifest -> {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
