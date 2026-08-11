#!/usr/bin/env python3
"""Fetch the first exact Laeken/Heysel/Bockstael UrbIS vector slice.

The slice is deliberately isolated from the Midi pipeline. Geometry comes from the
official Paradigm UrbIS vector WFS in Belgian Lambert 72 (EPSG:31370). Both the
cropped source GeoJSON and project-local metre coordinates are emitted so the
zone can be rebuilt reproducibly without hand-traced streets or buildings.
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from lambert72_to_game_geojson import (
    DEFAULT_ORIGIN_ALTITUDE,
    DEFAULT_ORIGIN_E,
    DEFAULT_ORIGIN_N,
    convert_document,
)

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
# Covers the first continuous hero corridor: Bockstael -> Heysel -> Atomium.
# Derived from sourced Bockstael/Heysel/Atomium anchors, then expanded to include
# surrounding junction geometry so WFS features are not clipped at the landmark.
DEFAULT_BBOX = (147_300.0, 173_650.0, 149_100.0, 176_750.0)
LAYERS = {
    "buildings": "urbisvector:Buildings",
    "street_surfaces": "urbisvector:StreetSurfaces",
    "street_axes": "urbisvector:StreetAxes",
    "tram_network": "urbisvector:TramNetwork",
    "train_network": "urbisvector:TrainNetwork",
    "bridges": "urbisvector:Bridges",
    "tunnels": "urbisvector:Tunnels",
}
REQUIRED_LAYERS = ("buildings", "street_surfaces", "street_axes", "tram_network")


def parse_bbox(raw: str) -> tuple[float, float, float, float]:
    values = tuple(float(item.strip()) for item in raw.split(","))
    if len(values) != 4:
        raise argparse.ArgumentTypeError("bbox must be minE,minN,maxE,maxN")
    min_e, min_n, max_e, max_n = values
    if min_e >= max_e or min_n >= max_n:
        raise argparse.ArgumentTypeError("bbox min values must be below max values")
    return min_e, min_n, max_e, max_n


def build_url(layer_name: str, bbox: tuple[float, float, float, float]) -> str:
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
    return f"{WFS_URL}?{urllib.parse.urlencode(params)}"


def fetch_layer(
    layer_name: str,
    bbox: tuple[float, float, float, float],
    retries: int = 3,
) -> tuple[dict[str, Any], str]:
    url = build_url(layer_name, bbox)
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": "GrandBruxellesGame-LaekenJette/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
                "Accept": "application/json,application/geo+json;q=0.9,*/*;q=0.1",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                payload = response.read()
            document = json.loads(payload.decode("utf-8"))
            if document.get("type") != "FeatureCollection":
                raise RuntimeError(
                    f"Unexpected UrbIS WFS response for {layer_name}: {document!r}"
                )
            return document, url
        except Exception as exc:  # pragma: no cover - network failure path
            last_error = exc
            if attempt < retries:
                time.sleep(float(attempt) * 2.0)
    raise RuntimeError(f"Unable to fetch {layer_name} after {retries} attempts") from last_error


def write_json(path: Path, document: dict[str, Any], *, pretty: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if pretty:
        text = json.dumps(document, ensure_ascii=False, indent=2) + "\n"
    else:
        text = json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\n"
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch exact UrbIS vector layers for the Laeken/Heysel/Bockstael first zone"
    )
    parser.add_argument(
        "--bbox",
        type=parse_bbox,
        default=DEFAULT_BBOX,
        help="EPSG:31370 minE,minN,maxE,maxN",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/urbis/laeken_jette"),
    )
    parser.add_argument("--origin-e", type=float, default=DEFAULT_ORIGIN_E)
    parser.add_argument("--origin-n", type=float, default=DEFAULT_ORIGIN_N)
    parser.add_argument("--origin-altitude", type=float, default=DEFAULT_ORIGIN_ALTITUDE)
    args = parser.parse_args()

    fetched_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    summary: dict[str, Any] = {
        "schema": 1,
        "format": "grand-bruxelles-urbis-laeken-jette-v1",
        "zone": "laeken_jette",
        "phase": "bockstael_heysel_atomium",
        "source": "Paradigm / Brussels-Capital Region UrbIS vector WFS",
        "source_dataset": "UrbIS vector",
        "source_license": "CC0 for UrbIS vector classes used here; cadastral parcels excluded",
        "wfs": WFS_URL,
        "source_crs": "EPSG:31370",
        "bbox": list(args.bbox),
        "fetched_at_utc": fetched_at,
        "game_origin": {
            "e": args.origin_e,
            "n": args.origin_n,
            "altitude": args.origin_altitude,
            "axes": "X=east, Y=up, Z=south",
            "units": "metres",
        },
        "layers": {},
    }

    for slug, layer_name in LAYERS.items():
        document, request_url = fetch_layer(layer_name, args.bbox)
        feature_count = len(document.get("features", []))
        document["grand_bruxelles_source"] = {
            "authority": "Paradigm / Brussels-Capital Region",
            "service": WFS_URL,
            "request_url": request_url,
            "layer": layer_name,
            "crs": "EPSG:31370",
            "bbox": list(args.bbox),
            "fetched_at_utc": fetched_at,
            "license": summary["source_license"],
        }
        raw_path = args.output_dir / f"{slug}.geojson"
        write_json(raw_path, document)

        game_document = convert_document(
            document,
            args.origin_e,
            args.origin_n,
            args.origin_altitude,
        )
        game_document["grand_bruxelles_source"] = document["grand_bruxelles_source"]
        game_path = args.output_dir / f"{slug}.game.json"
        write_json(game_path, game_document)

        summary["layers"][slug] = {
            "type_name": layer_name,
            "features": feature_count,
            "raw": raw_path.name,
            "game": game_path.name,
            "request_url": request_url,
        }
        print(f"{slug}: {feature_count} features")

    write_json(args.output_dir / "manifest.json", summary, pretty=True)

    missing = [
        slug for slug in REQUIRED_LAYERS if summary["layers"][slug]["features"] <= 0
    ]
    if missing:
        raise SystemExit(f"Required UrbIS layers empty: {', '.join(missing)}")

    print(f"UrbIS Laeken/Jette first slice ready: {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
