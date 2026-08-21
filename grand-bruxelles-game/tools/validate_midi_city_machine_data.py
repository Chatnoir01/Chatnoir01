#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

EXPECTED_BBOX = [147250.0, 168900.0, 148500.0, 170250.0]
EXPECTED_ORIGIN = {
    "e": 147868.29422791934,
    "n": 169538.62414926197,
    "altitude": 0.0,
    "axes": "X=east, Y=up, Z=south",
    "units": "metres",
}
REQUIRED_SLUGS = ("buildings", "street_surfaces", "street_axes", "train_network")


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
    print(f"MIDI_CITY_MACHINE_DATA_FAIL {message}", file=sys.stderr)
    return 2


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "data/urbis/midi"
    try:
        manifest = read_json(root / "manifest.json")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return fail(str(exc))

    if manifest.get("source_crs") != "EPSG:31370":
        return fail(f"source_crs={manifest.get('source_crs')!r}")
    if [float(v) for v in manifest.get("bbox", [])] != EXPECTED_BBOX:
        return fail(f"bbox={manifest.get('bbox')!r}")
    if manifest.get("game_origin") != EXPECTED_ORIGIN:
        return fail(f"game_origin={manifest.get('game_origin')!r}")
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
        if raw_count != expected or game_count != expected:
            return fail(f"{slug} count mismatch manifest={expected} raw={raw_count} game={game_count}")
        details.append(f"{slug}={expected}")

    compact_runtime = root / "midi_runtime.game.json"
    if not compact_runtime.is_file() or compact_runtime.stat().st_size <= 0:
        return fail("midi_runtime.game.json missing or empty")

    print(
        "MIDI_CITY_MACHINE_DATA_OK "
        + " ".join(details)
        + f" crs=EPSG:31370 bbox={EXPECTED_BBOX}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
