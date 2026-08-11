#!/usr/bin/env python3
"""Fetch a compact UrbIS WFS extract for Grand Bruxelles.

The script requests official UrbIS vector layers directly from Paradigm's WFS,
using Belgian Lambert 72 (EPSG:31370). It is intentionally bbox-based so each
city zone can be refreshed independently and kept small enough for CI/game use.

The public TramNetwork/TrainNetwork layers can expose overlapping rail features.
This GeoServer configuration rejects requests combining ``bbox`` and
``CQL_FILTER``, so spatial bbox fetching remains authoritative and rail features
are pruned immediately in memory before raw GeoJSON is written: TW for tramway,
RW for railway. Runtime classification repeats the same rule defensively.
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
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
LAYER_TYPE_FILTERS = {
    "urbisvector:TramNetwork": "TW",
    "urbisvector:TrainNetwork": "RW",
}


def parse_bbox(raw: str) -> tuple[float, float, float, float]:
    parts = [float(part.strip()) for part in raw.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("bbox must be minE,minN,maxE,maxN")
    min_e, min_n, max_e, max_n = parts
    if min_e >= max_e or min_n >= max_n:
        raise argparse.ArgumentTypeError("invalid bbox extent")
    return min_e, min_n, max_e, max_n


def build_request_params(
    layer_name: str,
    bbox: tuple[float, float, float, float],
) -> dict[str, str]:
    min_e, min_n, max_e, max_n = bbox
    return {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": layer_name,
        "outputFormat": "application/json",
        "srsName": "EPSG:31370",
        "bbox": f"{min_e},{min_n},{max_e},{max_n},EPSG:31370",
    }


def build_request_url(layer_name: str, bbox: tuple[float, float, float, float]) -> str:
    return WFS_URL + "?" + urllib.parse.urlencode(build_request_params(layer_name, bbox))


def _http_error_detail(exc: urllib.error.HTTPError) -> str:
    try:
        payload = exc.read()
        text = payload.decode("utf-8", errors="replace").strip()
    except Exception:
        text = ""
    if len(text) > 2000:
        text = text[:2000] + "…"
    return f"HTTP {exc.code}: {text or exc.reason}"


def _feature_type(feature: dict[str, Any]) -> str:
    properties = feature.get("properties") or {}
    return str(properties.get("TYPE") or properties.get("TYP") or "").strip().upper()


def prune_layer_features(layer_name: str, data: dict[str, Any]) -> tuple[dict[str, Any], int]:
    """Return a shallow FeatureCollection copy with irrelevant rail types removed."""
    required_type = LAYER_TYPE_FILTERS.get(layer_name)
    if not required_type:
        return data, 0

    original_features = list(data.get("features", []))
    kept = [feature for feature in original_features if _feature_type(feature) == required_type]
    pruned = dict(data)
    pruned["features"] = kept
    pruned["grand_bruxelles_filter"] = {
        "mode": "post_bbox_in_memory",
        "property": "TYPE",
        "equals": required_type,
        "source_features": len(original_features),
        "kept_features": len(kept),
        "removed_features": len(original_features) - len(kept),
    }
    return pruned, len(original_features) - len(kept)


def request_layer(layer_name: str, bbox: tuple[float, float, float, float], retries: int) -> dict:
    url = build_request_url(layer_name, bbox)
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
            "Accept": "application/geo+json, application/json",
        },
    )

    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                payload = response.read()
            data = json.loads(payload.decode("utf-8"))
            if data.get("type") != "FeatureCollection":
                raise RuntimeError(f"unexpected WFS payload for {layer_name}: {data.get('type')!r}")
            data, _ = prune_layer_features(layer_name, data)
            return data
        except urllib.error.HTTPError as exc:
            last_error = RuntimeError(_http_error_detail(exc))
        except Exception as exc:  # network/service failures are retriable in CI
            last_error = exc
        if attempt < retries:
            time.sleep(min(12, 2 ** attempt))
    raise RuntimeError(f"failed to fetch {layer_name} after {retries} attempts: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch official UrbIS WFS geometry for a game zone")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--bbox", type=parse_bbox, default=DEFAULT_BBOX)
    parser.add_argument("--retries", type=int, default=4)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "format": "grand-bruxelles-urbis-wfs-v2",
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
        filter_meta = data.get("grand_bruxelles_filter")
        manifest["layers"][short_name] = {
            "wfs_name": layer_name,
            "feature_filter": filter_meta,
            "features": count,
            "file": path.name,
        }
        print(f"{short_name}: {count} features -> {path}")

    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"manifest -> {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
