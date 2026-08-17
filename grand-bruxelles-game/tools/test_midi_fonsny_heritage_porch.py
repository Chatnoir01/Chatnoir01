#!/usr/bin/env python3
"""Fail-closed contract for the source-backed Fonsny heritage entrance porch."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
HERO = ROOT / "game/scripts/midi_hero_zone.gd"
MANIFEST = ROOT / "data/reconstruction/midi_source_manifest.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    hero = HERO.read_text(encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    heritage = next((source for source in manifest["sources"] if source.get("id") == "heritage_midi_9423"), None)
    require(heritage is not None, "heritage_midi_9423 source missing")
    require("component_reference" in heritage.get("role", []), "heritage source is not a component reference")

    # Source-backed identity from the Brussels architectural heritage inventory:
    # access porch with three registers, three long bays with concrete crosswork,
    # glass-block infill, and a broad concrete canopy.
    required_markers = [
        '"FonsnyHeritagePorch"',
        '"PorchBlindUpperRegister"',
        '"PorchGlassBlockBay_%02d"',
        '"PorchBayVerticalCross_%02d"',
        '"PorchBayHorizontalCross_%02d"',
        '"PorchPerforatedCanopy"',
        '"PorchPolygonalColumn_%02d"',
    ]
    for marker in required_markers:
        require(marker in hero, f"missing source-backed porch marker: {marker}")

    require("PORCH_BAY_COUNT := 3" in hero, "Fonsny heritage porch must expose exactly three long bays")
    require("PORCH_REGISTER_COUNT := 3" in hero, "Fonsny heritage porch must expose exactly three registers")
    require("GB_MIDI_FONSNY_PORCH_MODE" in hero, "same-head baseline/enhanced witness toggle missing")

    # Do not let the correction silently become a new station envelope claim.
    require("porch_dimensions_are_visualization_convention" in hero, "provisional dimension provenance marker missing")
    require(re.search(r"func _build_fonsny_heritage_porch\(", hero) is not None, "heritage porch builder missing")

    print("MIDI_FONSNY_HERITAGE_PORCH_OK: 3 registers, 3 bays, source identity locked")


if __name__ == "__main__":
    main()
