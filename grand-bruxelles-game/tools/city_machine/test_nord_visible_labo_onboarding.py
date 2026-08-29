#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
CATALOG = PROJECT / "data/qa/playable_zone_catalog.json"
RUNTIME = PROJECT / "game/zones/nord/nord_city_machine_zone.gd"
MANIFEST = PROJECT / "data/urbis/nord/manifest.json"

EXPECTED_COUNTS = {
    "buildings": 1015,
    "street_surfaces": 627,
    "street_axes": 168,
    "tram_network": 162,
    "train_network": 162,
}


def by_id(rows: list[dict], zone_id: str) -> dict:
    return next(row for row in rows if row.get("id") == zone_id)


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    labo = by_id(catalog["zones"], "nord_machine_labo")
    assert labo["label"] == "Gare du Nord — City Machine LABO"
    assert labo["quality"] == "LABO"
    assert labo["mode"] == "script_zone"
    assert labo["script"] == "res://game/zones/nord/nord_city_machine_zone.gd"
    assert labo["spawn"] == [1120.0, 1.05, -2440.0]
    assert labo["visual_review_only"] is True
    assert "review_alias_of" not in labo
    assert "JOUABLE" not in labo["label"]

    required = set(labo["requires"])
    expected_required = {
        "res://game/zones/nord/nord_city_machine_zone.gd",
        "res://data/urbis/nord/manifest.json",
        "res://data/urbis/nord/buildings.game.json",
        "res://data/urbis/nord/street_surfaces.game.json",
        "res://data/urbis/nord/street_axes.game.json",
        "res://data/urbis/nord/tram_network.game.json",
        "res://data/urbis/nord/train_network.game.json",
    }
    assert expected_required <= required
    for resource in expected_required:
        assert (PROJECT / resource.removeprefix("res://")).is_file(), resource

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert manifest["zone"] == "nord"
    assert manifest["source_crs"] == "EPSG:31370"
    assert manifest["promotion"] == "source_only_no_runtime_mutation"
    counts = {slug: int(manifest["layers"][slug]["features"]) for slug in EXPECTED_COUNTS}
    assert counts == EXPECTED_COUNTS

    runtime = RUNTIME.read_text(encoding="utf-8")
    for marker in (
        'DATA_ROOT := "res://data/urbis/nord"',
        'REVIEW_SPAWN := Vector3(1120.0, 1.05, -2440.0)',
        '"/buildings.game.json"',
        '"/street_surfaces.game.json"',
        '"/street_axes.game.json"',
        '"/tram_network.game.json"',
        '"/train_network.game.json"',
        "func _build_official_geometry",
        "create_trimesh_collision",
        "NORD_CITY_MACHINE_LABO_READY",
        "promotion=false",
    ):
        assert marker in runtime, marker
    assert "OSM_ENVIRONMENT_DATA" not in runtime
    assert "fast_travel" not in runtime

    print(
        "NORD_VISIBLE_LABO_ONBOARDING_OK "
        "visible_zone=nord_machine_labo official_urbis=true "
        "buildings=1015 street_surfaces=627 street_axes=168 "
        "tram_network=162 train_network=162 osm=false promotion=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
