#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
CATALOG = PROJECT / "data/qa/playable_zone_catalog.json"
REGISTRY = HERE / "registry.json"
RUNTIME = PROJECT / "game/zones/midi/midi_city_machine_zone.gd"
OSM = PROJECT / "data/osm/zones/midi/environment.game.json"
PREFLIGHT = HERE / "check_onboarding_candidate.py"
MACHINE = HERE / "city_machine.py"


def by_id(rows: list[dict], zone_id: str) -> dict:
    return next(row for row in rows if row.get("id") == zone_id)


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    canonical = by_id(catalog["zones"], "midi")
    labo = by_id(catalog["zones"], "midi_machine_labo")

    assert canonical == {
        "id": "midi",
        "label": "Midi",
        "quality": "JOUABLE",
        "mode": "fast_travel",
        "destination": "midi",
        "requires": [
            "res://game/main.tscn",
            "res://game/scripts/player_controller.gd",
        ],
    }, "canonical Midi must remain unchanged"

    assert labo["quality"] == "LABO"
    assert labo["mode"] == "script_zone"
    assert labo["script"] == "res://game/zones/midi/midi_city_machine_zone.gd"
    assert labo["spawn"] == [-600.0, 1.05, 600.0]
    assert "JOUABLE" not in labo["label"]

    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    profile = registry["zone_profiles"]["midi"]
    assert profile["source_root"] == "data/urbis/midi"
    assert profile["runtime_script"] == "game/zones/midi/midi_city_machine_zone.gd"
    assert profile["osm_environment"]["runtime"] == "data/osm/zones/midi/environment.game.json"

    runtime = RUNTIME.read_text(encoding="utf-8")
    for path in (
        'DATA_ROOT := "res://data/urbis/midi"',
        '"/buildings.game.json"',
        '"/street_surfaces.game.json"',
        'OSM_ENVIRONMENT_DATA := "res://data/osm/zones/midi/environment.game.json"',
        "func _make_materials",
        "func _build_ground_reference",
        "func _build_official_geometry",
    ):
        assert path in runtime, path
    assert "midi_runtime.game.json" not in runtime
    assert "urbis_midi_builder.gd" not in runtime
    assert "promotion=false" in runtime

    osm = json.loads(OSM.read_text(encoding="utf-8"))
    assert osm["zone"] == "midi"
    assert osm["bbox_31370"] == [147250.0, 168900.0, 148500.0, 170250.0]
    assert osm["stats"] == {
        "tree": 1694,
        "street_lamp": 104,
        "bollard": 732,
        "total": 2530,
    }

    preflight = subprocess.run(
        [sys.executable, str(PREFLIGHT), "--zone", "midi"],
        cwd=PROJECT, text=True, capture_output=True,
    )
    assert preflight.returncode == 0, (preflight.stdout, preflight.stderr)
    report = json.loads(preflight.stdout)
    assert report["eligible"] is True
    assert report["promotion_performed"] is False

    dry = subprocess.run(
        [sys.executable, str(MACHINE), "build", "--zone", "midi", "--dry-run"],
        cwd=PROJECT, text=True, capture_output=True,
    )
    assert dry.returncode == 0, (dry.stdout, dry.stderr)
    assert "CITY_MACHINE_OK zone=midi mode=dry-run gates=5 promotion=false" in dry.stdout

    print(
        "MIDI_VISIBLE_LABO_ONBOARDING_OK "
        "machine_zone=midi visible_zone=midi_machine_labo "
        "canonical_midi_jouable_unchanged=true osm_points=2530 "
        "preflight=true gates=5 promotion=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
