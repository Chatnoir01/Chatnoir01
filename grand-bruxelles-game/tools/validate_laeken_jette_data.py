#!/usr/bin/env python3
"""Validate the committed Laeken/Jette UrbIS slice before Godot consumes it."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

EXPECTED_BBOX = [147300.0, 173650.0, 149100.0, 176750.0]
REQUIRED = ("buildings", "street_surfaces", "street_axes", "tram_network")


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def validate(root: Path) -> dict[str, int]:
    manifest = load(root / "manifest.json")
    assert manifest["source_crs"] == "EPSG:31370", manifest.get("source_crs")
    assert manifest["bbox"] == EXPECTED_BBOX, manifest.get("bbox")
    assert manifest["game_origin"]["units"] == "metres"
    assert manifest["game_origin"]["axes"] == "X=east, Y=up, Z=south"

    counts: dict[str, int] = {}
    for slug, info in manifest["layers"].items():
        raw = load(root / info["raw"])
        game = load(root / info["game"])
        raw_count = len(raw.get("features", []))
        game_count = len(game.get("features", []))
        assert raw_count == game_count == int(info["features"]), (slug, raw_count, game_count, info)
        assert game["grand_bruxelles_coordinate_system"]["source_crs"] == "EPSG:31370"
        assert game["grand_bruxelles_coordinate_system"]["units"] == "metres"
        assert raw.get("grand_bruxelles_source", {}).get("authority") == "Paradigm / Brussels-Capital Region"
        counts[slug] = raw_count

    empty = [slug for slug in REQUIRED if counts.get(slug, 0) <= 0]
    assert not empty, f"required layers are empty: {empty}"
    assert counts["buildings"] >= 100, counts
    assert counts["street_axes"] >= 50, counts
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path, default=Path("data/urbis/laeken_jette"))
    args = parser.parse_args()
    counts = validate(args.root)
    print("LAEKEN_JETTE_DATA_OK", counts)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
