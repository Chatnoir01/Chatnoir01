#!/usr/bin/env python3
"""Fail-closed contract for the source-backed Fonsny heritage entrance porch."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game/scripts/midi_fonsny_heritage_porch_runtime.gd"
MOUNT = ROOT / "game/scripts/midi_architectural_concrete_surface_runtime.gd"
MANIFEST = ROOT / "data/reconstruction/midi_source_manifest.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    require(RUNTIME.exists(), "Fonsny heritage porch runtime missing")
    runtime = RUNTIME.read_text(encoding="utf-8")
    mount = MOUNT.read_text(encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    heritage = next((s for s in manifest["sources"] if s.get("id") == "heritage_midi_9423"), None)
    require(heritage is not None, "heritage_midi_9423 source missing")
    require("component_reference" in heritage.get("role", []), "heritage source is not a component reference")
    for marker in [
        '"FonsnyHeritagePorch"', '"PorchBlindUpperRegister"',
        '"PorchGlassBlockBay_%02d"', '"PorchBayVerticalCross_%02d"',
        '"PorchBayHorizontalCross_%02d"', '"PorchPerforatedCanopy"',
        '"PorchPolygonalColumn_%02d"',
    ]:
        require(marker in runtime, f"missing source-backed porch marker: {marker}")
    require("PORCH_BAY_COUNT := 3" in runtime, "porch must expose exactly three long bays")
    require("PORCH_REGISTER_COUNT := 3" in runtime, "porch must expose exactly three registers")
    require("GB_MIDI_FONSNY_PORCH_MODE" in runtime, "same-head baseline/enhanced witness toggle missing")
    require("porch_dimensions_are_visualization_convention" in runtime, "provisional dimension provenance marker missing")
    require(re.search(r"func _build_fonsny_heritage_porch\(", runtime) is not None, "heritage porch builder missing")
    require("midi_fonsny_heritage_porch_runtime.gd" in mount, "Midi-only runtime mount missing")
    require("geometry_changed" in mount, "existing material provenance guard unexpectedly removed")
    print("MIDI_FONSNY_HERITAGE_PORCH_OK: 3 registers, 3 bays, source identity locked")


if __name__ == "__main__":
    main()
