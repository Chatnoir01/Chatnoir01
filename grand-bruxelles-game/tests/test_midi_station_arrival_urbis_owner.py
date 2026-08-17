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
    rows = [r for r in data["buildings"] if r["id"] == STATION_ID]
    assert len(rows) == 1 and rows[0]["area"] == 9949.0
    assert rows[0]["height_source"] == "temporary_area_heuristic"
    main_scene = MAIN.read_text(encoding="utf-8")
    assert '[node name="UrbISMidiExact"' in main_scene and '[node name="MidiHeroZone"' in main_scene
    hero = MATERIAL_LAYER.read_text(encoding="utf-8")
    code = [line.split("#", 1)[0].strip() for line in hero.splitlines()]
    assert "MIDI_URBIS_ENVELOPE_OWNER := true" in hero
    assert not any("super._ready()" in line for line in code)
    assert not any("_build_station_complex()" in line for line in code)
    for required in ["_build_station_entrance()", "_build_fonsny_forecourt()", "_build_fonsny_crossing()", "_build_fonsny_street_furniture()", "_build_shelters()", "_build_tram_railings()"]:
        assert any(required in line for line in code), required
    print("MIDI_STATION_URBIS_OWNER_OK station=1633645 area=9949 plan=official_urbis height=temporary_area_heuristic")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
