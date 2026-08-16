#!/usr/bin/env python3
"""Fetch the official UrbIS Jette phase-2 slice in EPSG:31370.

Scope: Place Reine Astrid/Miroir, Avenue de Jette, Chaussée de Wemmel,
Jette station/rail corridor and Parc Roi Baudouin. This deliberately remains a
separate dataset from the validated Laeken phase-1 corridor.
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
DEFAULT_BBOX = (144_900.0, 173_000.0, 147_700.0, 175_300.0)
LAYERS = {
    "buildings": "urbisvector:Buildings",
    "street_surfaces": "urbisvector:StreetSurfaces",
    "street_axes": "urbisvector:StreetAxes",
    "tram_network": "urbisvector:TramNetwork",
    "train_network": "urbisvector:TrainNetwork",
    "bridges": "urbisvector:Bridges",
    "tunnels": "urbisvector:Tunnels",
}
REQUIRED_LAYERS = ("buildings", "street_surfaces", "street_axes", "train_network")


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


def fetch_layer(layer_name: str, bbox: tuple[float, float, float, float], retries: int = 3) -> tuple[dict[str, Any], str]:
    url = build_url(layer_name, bbox)
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": "GrandBruxellesGame-Jette/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
                "Accept": "application/json,application/geo+json;q=0.9,*/*;q=0.1",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                payload = response.read()
            document = json.loads(payload.decode("utf-8"))
            if document.get("type") != "FeatureCollection":
                raise RuntimeError(f"Unexpected UrbIS WFS response for {layer_name}: {document!r}")
            return document, url
        except Exception as exc:  # pragma: no cover - network failure path
            last_error = exc
            if attempt < retries:
                time.sleep(float(attempt) * 2.0)
    raise RuntimeError(f"Unable to fetch {layer_name} after {retries} attempts") from last_error


def write_json(path: Path, document: dict[str, Any], *, pretty: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(
        document,
        ensure_ascii=False,
        indent=2 if pretty else None,
        separators=None if pretty else (",", ":"),
    ) + "\n"
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch exact UrbIS vector layers for Jette phase 2")
    parser.add_argument("--bbox", type=parse_bbox, default=DEFAULT_BBOX)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/urbis/laeken_jette/jette_phase2"),
    )
    parser.add_argument("--origin-e", type=float, default=DEFAULT_ORIGIN_E)
    parser.add_argument("--origin-n", type=float, default=DEFAULT_ORIGIN_N)
    parser.add_argument("--origin-altitude", type=float, default=DEFAULT_ORIGIN_ALTITUDE)
    args = parser.parse_args()

    fetched_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    manifest: dict[str, Any] = {
        "schema": 1,
        "format": "grand-bruxelles-urbis-laeken-jette-v1",
        "zone": "laeken_jette",
        "phase": "jette_miroir_station_roi_baudouin",
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
        count = len(document.get("features", []))
        provenance = {
            "authority": "Paradigm / Brussels-Capital Region",
            "service": WFS_URL,
            "request_url": request_url,
            "layer": layer_name,
            "crs": "EPSG:31370",
            "bbox": list(args.bbox),
            "fetched_at_utc": fetched_at,
            "license": manifest["source_license"],
        }
        document["grand_bruxelles_source"] = provenance
        raw_path = args.output_dir / f"{slug}.geojson"
        write_json(raw_path, document)

        game_document = convert_document(document, args.origin_e, args.origin_n, args.origin_altitude)
        game_document["grand_bruxelles_source"] = provenance
        game_path = args.output_dir / f"{slug}.game.json"
        write_json(game_path, game_document)

        manifest["layers"][slug] = {
            "type_name": layer_name,
            "features": count,
            "raw": raw_path.name,
            "game": game_path.name,
            "request_url": request_url,
        }
        print(f"{slug}: {count} features")

    write_json(args.output_dir / "manifest.json", manifest, pretty=True)
    missing = [slug for slug in REQUIRED_LAYERS if manifest["layers"][slug]["features"] <= 0]
    if missing:
        raise SystemExit(f"Required Jette UrbIS layers empty: {', '.join(missing)}")
    print(f"UrbIS Jette phase 2 ready: {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
