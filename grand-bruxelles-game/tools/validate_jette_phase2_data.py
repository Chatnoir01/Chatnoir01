#!/usr/bin/env python3
"""Validate cached official UrbIS zone data and project-local conversion.

Keeps the original strict Jette assertions while also accepting profile-driven
UrbIS manifests used by City Machine v4 (for example Midi).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

JETTE_EXPECTED_BBOX = [144900.0, 173000.0, 147700.0, 175300.0]
REQUIRED = ("buildings", "street_surfaces", "street_axes", "train_network")


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _layer_paths(info: dict[str, Any], slug: str) -> tuple[str, str]:
    raw_name = str(info.get("raw") or info.get("file") or f"{slug}.geojson")
    game_name = str(info.get("game") or f"{slug}.game.json")
    return raw_name, game_name


def validate(root: Path) -> dict[str, int]:
    manifest = load(root / "manifest.json")
    is_jette = manifest.get("phase") == "jette_miroir_station_roi_baudouin"

    assert manifest["source_crs"] == "EPSG:31370"
    assert str(manifest.get("source_license", "")).strip()
    if is_jette:
        assert manifest["bbox"] == JETTE_EXPECTED_BBOX, manifest.get("bbox")
    else:
        bbox = manifest.get("bbox")
        assert isinstance(bbox, list) and len(bbox) == 4, bbox
        assert float(bbox[0]) < float(bbox[2]) and float(bbox[1]) < float(bbox[3]), bbox

    origin = manifest["game_origin"]
    assert origin["units"] == "metres"
    assert origin["axes"] == "X=east, Y=up, Z=south"

    counts: dict[str, int] = {}
    layers = manifest.get("layers") or {}
    for slug, info in layers.items():
        if slug not in REQUIRED:
            continue
        raw_name, game_name = _layer_paths(info, slug)
        raw = load(root / raw_name)
        game = load(root / game_name)
        raw_count = len(raw.get("features", []))
        game_count = len(game.get("features", []))
        assert raw_count == game_count == int(info["features"]), (slug, raw_count, game_count)
        coord = game["grand_bruxelles_coordinate_system"]
        assert coord["source_crs"] == "EPSG:31370"
        assert coord["units"] == "metres"
        assert coord["axes"] == "X=east, Y=up, Z=south"
        assert float(coord["origin_e"]) == float(origin["e"]), (slug, coord.get("origin_e"), origin["e"])
        assert float(coord["origin_n"]) == float(origin["n"]), (slug, coord.get("origin_n"), origin["n"])
        if is_jette:
            assert raw.get("grand_bruxelles_source", {}).get("authority") == "Paradigm / Brussels-Capital Region"
        counts[slug] = raw_count

    empty = [slug for slug in REQUIRED if counts.get(slug, 0) <= 0]
    assert not empty, f"required UrbIS layers are empty: {empty}"
    assert counts["buildings"] >= 100, counts
    assert counts["street_axes"] >= 50, counts
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "root",
        nargs="?",
        type=Path,
        default=Path("data/urbis/laeken_jette/jette_phase2"),
    )
    args = parser.parse_args()
    counts = validate(args.root)
    label = "JETTE_PHASE2_DATA_OK" if args.root.name == "jette_phase2" else "URBIS_ZONE_DATA_OK"
    print(label, counts)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
