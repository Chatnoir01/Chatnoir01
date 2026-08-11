#!/usr/bin/env python3
"""Fetch a compact UrbIS WFS extract for Grand Bruxelles.

The script requests official UrbIS vector layers directly from Paradigm's WFS,
using Belgian Lambert 72 (EPSG:31370). It is intentionally bbox-based so each
city zone can be refreshed independently and kept small enough for CI/game use.
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
DEFAULT_BBOX = (147250.0, 168900.0, 148500.0, 170250.0)
DEFAULT_LAYERS = {
    "buildings": "urbisvector:Buildings",
    "street_surfaces": "urbisvector:StreetSurfaces",
    "street_axes": "urbisvector:StreetAxes",
    "tram_network": "urbisvector:TramNetwork",
    "train_network": "urbisvector:TrainNetwork",
}


def parse_bbox(raw: str) -> tuple[float, float, float, float]:
    parts = [float(part.strip()) for part in raw.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("bbox must be minE,minN,maxE,maxN")
    min_e, min_n, max_e, max_n = parts
    if min_e >= max_e or min_n >= max_n:
        raise argparse.ArgumentTypeError("invalid bbox extent")
    return min_e, min_n, max_e, max_n


def request_layer(layer_name: str, bbox: tuple[float, float, float, float], retries: int) -> dict:
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
            return data
        except Exception as exc:  # network/service failures are retriable in CI
            last_error = exc
            if attempt >= retries:
                break
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
        }
        print(f"{short_name}: {count} features -> {path}")

    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"manifest -> {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
