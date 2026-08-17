#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "data" / "urbis" / "midi" / "midi_runtime.game.json"
MAIN = ROOT / "game" / "main.tscn"
MATERIAL_LAYER = ROOT / "game" / "scripts" / "midi_hero_zone_materials.gd"
STATION_ID = "https://databrussels.be/id/building/1633645"


def main() -> int:
    data = json.loads(RUNTIME.read_text(encoding="utf-8"))
    assert data["accuracy"]["plan_geometry"] == "official_urbis"
    assert data["accuracy"]["building_heights"].startswith("temporary_area_heuristic")
    station = [row for row in data["buildings"] if row["id"] == STATION_ID]
    assert len(station) == 1
    assert station[0]["area"] == 9949.0
    assert station[0]["height_source"] == "temporary_area_heuristic"

    main_scene = MAIN.read_text(encoding="utf-8")
    assert '[node name="UrbISMidiExact"' in main_scene
    assert '[node name="MidiHeroZone"' in main_scene

    hero = MATERIAL_LAYER.read_text(encoding="utf-8")
    # Production material/hero layer must not invoke the inherited hand-built
    # station complex when official UrbIS geometry is active.
    assert "MIDI_URBIS_ENVELOPE_OWNER := true" in hero, "red-first: UrbIS envelope owner guard missing"
    assert "super._ready()" not in hero, "red-first: inherited hand-built station complex still active"
    assert "_build_station_complex()" not in hero, "red-first: hand-built station complex still invoked"
    for required in (
        "_build_station_entrance()",
        "_build_fonsny_forecourt()",
        "_build_fonsny_crossing()",
        "_build_fonsny_street_furniture()",
        "_build_shelters()",
        "_build_tram_railings()",
    ):
        assert required in hero, f"street-level Midi detail lost: {required}"

    print("MIDI_STATION_URBIS_OWNER_OK station=1633645 area=9949 plan=official_urbis height=temporary_area_heuristic")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
