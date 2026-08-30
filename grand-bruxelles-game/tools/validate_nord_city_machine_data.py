#!/usr/bin/env python3
"""Fail-closed source validator for the Gare du Nord City Machine candidate."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

EXPECTED_BBOX = [149000.0, 172000.0, 150000.0, 172500.0]
EXPECTED_ORIGIN = {
    "e": 149500.0,
    "n": 172250.0,
    "altitude": 0.0,
    "axes": "X=east, Y=up, Z=south",
    "units": "metres",
}
EXPECTED_WFS = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
REQUIRED_SLUGS = (
    "buildings",
    "street_surfaces",
    "street_axes",
    "tram_network",
    "train_network",
)


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def feature_count(path: Path) -> int:
    value = read_json(path)
    features = value.get("features")
    if value.get("type") != "FeatureCollection" or not isinstance(features, list):
        raise ValueError(f"not a FeatureCollection: {path}")
    return len(features)


def fail(message: str) -> int:
    print(f"NORD_CITY_MACHINE_DATA_FAIL {message}", file=sys.stderr)
    return 2


def main() -> int:
    root = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else Path(__file__).resolve().parents[1] / "data/urbis/nord"
    )
    try:
        manifest = read_json(root / "manifest.json")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return fail(str(exc))

    if manifest.get("format") != "grand-bruxelles-urbis-wfs-v1":
        return fail(f"format={manifest.get('format')!r}")
    if manifest.get("source") != EXPECTED_WFS:
        return fail(f"source={manifest.get('source')!r}")
    if manifest.get("source_crs") != "EPSG:31370" or manifest.get("crs") != "EPSG:31370":
        return fail("CRS contract mismatch")
    if [float(v) for v in manifest.get("bbox", [])] != EXPECTED_BBOX:
        return fail(f"bbox={manifest.get('bbox')!r}")
    if manifest.get("game_origin") != EXPECTED_ORIGIN:
        return fail(f"game_origin={manifest.get('game_origin')!r}")
    origin = manifest["game_origin"]
    min_e, min_n, max_e, max_n = EXPECTED_BBOX
    if not (min_e <= float(origin["e"]) <= max_e and min_n <= float(origin["n"]) <= max_n):
        return fail("game_origin outside Nord acquisition bbox")
    if manifest.get("zone") != "nord":
        return fail(f"zone={manifest.get('zone')!r}")
    if manifest.get("promotion") != "source_only_no_runtime_mutation":
        return fail(f"promotion={manifest.get('promotion')!r}")
    if not str(manifest.get("source_license", "")).strip():
        return fail("source_license missing")

    layers = manifest.get("layers")
    if not isinstance(layers, dict):
        return fail("layers missing")

    details: list[str] = []
    for slug in REQUIRED_SLUGS:
        layer = layers.get(slug)
        if not isinstance(layer, dict):
            return fail(f"manifest layer missing: {slug}")
        raw = root / f"{slug}.geojson"
        game = root / f"{slug}.game.json"
        if not raw.is_file() or not game.is_file():
            return fail(f"materialized pair missing: {slug}")
        try:
            raw_count = feature_count(raw)
            game_count = feature_count(game)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            return fail(str(exc))
        expected = int(layer.get("features", -1))
        if expected <= 0:
            return fail(f"required layer empty: {slug}")
        if raw_count != expected or game_count != expected:
            return fail(
                f"{slug} count mismatch manifest={expected} raw={raw_count} game={game_count}"
            )
        try:
            game_doc = read_json(game)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            return fail(str(exc))
        coord = game_doc.get("grand_bruxelles_coordinate_system")
        if not isinstance(coord, dict) or coord.get("source_crs") != "EPSG:31370":
            return fail(f"game coordinate contract missing: {slug}")
        game_origin = coord.get("origin")
        if not isinstance(game_origin, dict):
            return fail(f"game origin metadata missing: {slug}")
        if float(game_origin.get("e", float("nan"))) != EXPECTED_ORIGIN["e"]:
            return fail(f"game origin e mismatch: {slug}")
        if float(game_origin.get("n", float("nan"))) != EXPECTED_ORIGIN["n"]:
            return fail(f"game origin n mismatch: {slug}")
        details.append(f"{slug}={expected}")

    print(
        "NORD_CITY_MACHINE_DATA_OK "
        + " ".join(details)
        + f" crs=EPSG:31370 bbox={EXPECTED_BBOX} origin=149500,172250 promotion=source_only"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
