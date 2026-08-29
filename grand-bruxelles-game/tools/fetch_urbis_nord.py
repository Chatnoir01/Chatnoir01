#!/usr/bin/env python3
"""Acquire the Gare du Nord bootstrap envelope from the official UrbIS WFS.

This is a source-acquisition tool, not a runtime promotion tool. It persists
only official vector source geometry plus deterministic game-local transforms.
No synthetic station geometry is authored here.
"""
from __future__ import annotations

import argparse
import json
import time
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
DEFAULT_BBOX = (149000.0, 172000.0, 150000.0, 172500.0)
SOURCE_LICENSE = "CC0-1.0 (UrbIS vector layers used by this source root)"
LAYERS = {
    "buildings": "urbisvector:Buildings",
    "street_surfaces": "urbisvector:StreetSurfaces",
    "street_axes": "urbisvector:StreetAxes",
    "tram_network": "urbisvector:TramNetwork",
    "train_network": "urbisvector:TrainNetwork",
}
REQUIRED_NONEMPTY = tuple(LAYERS)


def parse_bbox(raw: str) -> tuple[float, float, float, float]:
    values = tuple(float(item.strip()) for item in raw.split(","))
    if len(values) != 4:
        raise argparse.ArgumentTypeError("bbox must be minE,minN,maxE,maxN")
    min_e, min_n, max_e, max_n = values
    if min_e >= max_e or min_n >= max_n:
        raise argparse.ArgumentTypeError("bbox min values must be below max values")
    return min_e, min_n, max_e, max_n


def fetch_layer(
    layer_name: str,
    bbox: tuple[float, float, float, float],
    retries: int,
) -> dict[str, Any]:
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
            "User-Agent": "GrandBruxellesGame/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
            "Accept": "application/json,application/geo+json;q=0.9,*/*;q=0.1",
        },
    )
    last_error: Exception | None = None
    for attempt in range(1, max(1, retries) + 1):
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                payload = response.read()
            document = json.loads(payload.decode("utf-8"))
            if document.get("type") != "FeatureCollection":
                raise RuntimeError(
                    f"unexpected UrbIS WFS response for {layer_name}: {document.get('type')!r}"
                )
            return document
        except Exception as exc:  # explicit network/service retry path
            last_error = exc
            if attempt >= max(1, retries):
                break
            time.sleep(min(12, 2**attempt))
    raise RuntimeError(f"failed to fetch {layer_name}: {last_error}")


def write_json(path: Path, document: dict[str, Any], *, pretty: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if pretty:
        payload = json.dumps(document, ensure_ascii=False, indent=2)
    else:
        payload = json.dumps(document, ensure_ascii=False, separators=(",", ":"))
    path.write_text(payload + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch official UrbIS vector layers for the Gare du Nord bootstrap envelope"
    )
    parser.add_argument("--bbox", type=parse_bbox, default=DEFAULT_BBOX)
    parser.add_argument("--output-dir", type=Path, default=Path("data/urbis/nord"))
    parser.add_argument("--retries", type=int, default=4)
    parser.add_argument("--origin-e", type=float, default=DEFAULT_ORIGIN_E)
    parser.add_argument("--origin-n", type=float, default=DEFAULT_ORIGIN_N)
    parser.add_argument("--origin-altitude", type=float, default=DEFAULT_ORIGIN_ALTITUDE)
    args = parser.parse_args()

    manifest: dict[str, Any] = {
        "format": "grand-bruxelles-urbis-wfs-v1",
        "source": WFS_URL,
        "crs": "EPSG:31370",
        "source_crs": "EPSG:31370",
        "source_license": SOURCE_LICENSE,
        "game_origin": {
            "e": args.origin_e,
            "n": args.origin_n,
            "altitude": args.origin_altitude,
            "axes": "X=east, Y=up, Z=south",
            "units": "metres",
        },
        "bbox": list(args.bbox),
        "zone": "nord",
        "promotion": "source_only_no_runtime_mutation",
        "layers": {},
    }

    for slug, layer_name in LAYERS.items():
        document = fetch_layer(layer_name, args.bbox, args.retries)
        feature_count = len(document.get("features", []))
        document["grand_bruxelles_source"] = {
            "authority": "Paradigm / Brussels-Capital Region",
            "service": WFS_URL,
            "layer": layer_name,
            "license": SOURCE_LICENSE,
            "crs": "EPSG:31370",
            "bbox": list(args.bbox),
            "zone": "nord",
        }
        raw_path = args.output_dir / f"{slug}.geojson"
        write_json(raw_path, document)

        game_document = convert_document(
            document,
            args.origin_e,
            args.origin_n,
            args.origin_altitude,
        )
        game_document["grand_bruxelles_source"] = dict(document["grand_bruxelles_source"])
        game_path = args.output_dir / f"{slug}.game.json"
        write_json(game_path, game_document)

        manifest["layers"][slug] = {
            "wfs_name": layer_name,
            "features": feature_count,
            "file": raw_path.name,
            "game_file": game_path.name,
        }
        print(f"nord {slug}: {feature_count} features")

    missing = [
        slug
        for slug in REQUIRED_NONEMPTY
        if int(manifest["layers"][slug]["features"]) <= 0
    ]
    if missing:
        raise SystemExit(f"Required Gare du Nord UrbIS layers empty: {', '.join(missing)}")

    write_json(args.output_dir / "manifest.json", manifest, pretty=True)
    print(f"NORD_URBIS_SOURCE_OK root={args.output_dir} bbox={list(args.bbox)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
