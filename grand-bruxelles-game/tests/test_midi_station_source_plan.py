#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "data" / "urbis" / "midi" / "midi_runtime.game.json"
HERO = ROOT / "game" / "scripts" / "midi_hero_zone.gd"
STATION_ID = "https://databrussels.be/id/building/1633645"


def main() -> int:
    data = json.loads(RUNTIME.read_text(encoding="utf-8"))
    assert data["accuracy"]["plan_geometry"] == "official_urbis"
    assert data["accuracy"]["building_heights"].startswith("temporary_area_heuristic")

    rows = [row for row in data["buildings"] if row["id"] == STATION_ID]
    assert len(rows) == 1
    station = rows[0]
    assert station["area"] == 9949.0
    assert station["height_source"] == "temporary_area_heuristic"
    assert len(station["footprint"]) >= 100

    hero = HERO.read_text(encoding="utf-8")
    assert 'MIDI_STATION_BUILDING_ID := "https://databrussels.be/id/building/1633645"' in hero
    assert "_source_station_footprint" in hero
    assert 'Vector3(45.0, 3.25, 171.0)' not in hero
    assert 'Vector3(44.6, 4.1, 170.0)' not in hero
    assert 'Vector3(48.0, 0.55, 176.0)' not in hero
    assert "temporary_area_heuristic" in hero
    print("MIDI_STATION_SOURCE_PLAN_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
