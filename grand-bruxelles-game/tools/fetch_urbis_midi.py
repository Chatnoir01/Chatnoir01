#!/usr/bin/env python3
"""Fetch an exact Bruxelles-Midi vector slice from the official UrbIS WFS.

The goal is to stop relying on approximate OSM road widths/footprints inside the
hero zone. GeoServer returns EPSG:31370 GeoJSON for a tight Midi bounding box;
we also emit game-local copies using the project's Lambert72 origin.
"""

from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from lambert72_to_game_geojson import (
    DEFAULT_ORIGIN_ALTITUDE,
    DEFAULT_ORIGIN_E,
    DEFAULT_ORIGIN_N,
    convert_document,
)

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
DEFAULT_BBOX = (147_500.0, 169_150.0, 148_250.0, 169_950.0)
LAYERS = {
    "buildings": "urbisvector:Buildings",
    "street_surfaces": "urbisvector:StreetSurfaces",
    "street_axes": "urbisvector:StreetAxes",
    "tram_network": "urbisvector:TramNetwork",
    "train_network": "urbisvector:TrainNetwork",
    "bridges": "urbisvector:Bridges",
    "tunnels": "urbisvector:Tunnels",
}


def parse_bbox(raw: str) -> tuple[float, float, float, float]:
    values = tuple(float(item.strip()) for item in raw.split(","))
    if len(values) != 4:
        raise argparse.ArgumentTypeError("bbox must be minE,minN,maxE,maxN")
    min_e, min_n, max_e, max_n = values
    if min_e >= max_e or min_n >= max_n:
        raise argparse.ArgumentTypeError("bbox min values must be below max values")
    return min_e, min_n, max_e, max_n


def fetch_layer(layer_name: str, bbox: tuple[float, float, float, float]) -> dict[str, Any]:
    min_e, min_n, max_e, max_n = bbox
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": layer_name,
        "srsName": "EPSG:31370",
        "bbox": f"{min_e},{min_n},{max_e},{max_n},EPSG:31370",
        "outputFormat": "application/json",
        "count": "20000",
    }
    url = f"{WFS_URL}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "GrandBruxellesGame/0.8 (+https://github.com/Chatnoir01/Chatnoir01)",
            "Accept": "application/json,application/geo+json;q=0.9,*/*;q=0.1",
        },
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        payload = response.read()
    document = json.loads(payload.decode("utf-8"))
    if document.get("type") != "FeatureCollection":
        raise RuntimeError(f"Unexpected UrbIS WFS response for {layer_name}: {document!r}")
    return document


def write_json(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch exact UrbIS vector layers around Bruxelles-Midi")
    parser.add_argument(
        "--bbox",
        type=parse_bbox,
        default=DEFAULT_BBOX,
        help="EPSG:31370 minE,minN,maxE,maxN",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/urbis/midi"),
    )
    parser.add_argument("--origin-e", type=float, default=DEFAULT_ORIGIN_E)
    parser.add_argument("--origin-n", type=float, default=DEFAULT_ORIGIN_N)
    parser.add_argument("--origin-altitude", type=float, default=DEFAULT_ORIGIN_ALTITUDE)
    args = parser.parse_args()

    summary: dict[str, Any] = {
        "format": "grand-bruxelles-urbis-midi-v1",
        "source": "Paradigm / Brussels-Capital Region UrbIS vector WFS",
        "wfs": WFS_URL,
        "source_crs": "EPSG:31370",
        "bbox": list(args.bbox),
        "game_origin": {
            "e": args.origin_e,
            "n": args.origin_n,
            "altitude": args.origin_altitude,
        },
        "layers": {},
    }

    for slug, layer_name in LAYERS.items():
        document = fetch_layer(layer_name, args.bbox)
        feature_count = len(document.get("features", []))
        document["grand_bruxelles_source"] = {
            "authority": "Paradigm / Brussels-Capital Region",
            "service": WFS_URL,
            "layer": layer_name,
            "crs": "EPSG:31370",
            "bbox": list(args.bbox),
        }
        raw_path = args.output_dir / f"{slug}.geojson"
        write_json(raw_path, document)

        game_document = convert_document(
            document,
            args.origin_e,
            args.origin_n,
            args.origin_altitude,
        )
        game_path = args.output_dir / f"{slug}.game.json"
        write_json(game_path, game_document)

        summary["layers"][slug] = {
            "type_name": layer_name,
            "features": feature_count,
            "raw": raw_path.name,
            "game": game_path.name,
        }
        print(f"{slug}: {feature_count} features")

    write_json(args.output_dir / "manifest.json", summary)

    required = ("buildings", "street_surfaces", "street_axes", "tram_network", "train_network")
    missing = [slug for slug in required if summary["layers"][slug]["features"] <= 0]
    if missing:
        raise SystemExit(f"Required UrbIS layers empty: {', '.join(missing)}")

    print(f"UrbIS Midi slice ready: {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
