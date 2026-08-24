#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

import build_runtime_environment_index as rei

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
INDEX = PROJECT / "data/runtime/runtime_environment_index.json"
MODULE = PROJECT / "data/runtime/modules/city_machine_environment.json"
BRIDGE = PROJECT / "game/scripts/brussels_city_machine_environment_runtime.gd"
RENDERER = PROJECT / "game/scripts/brussels_osm_environment_runtime.gd"


def main() -> int:
    generated = rei.build_index()
    committed = json.loads(INDEX.read_text(encoding="utf-8"))
    assert generated == committed
    assert generated["format"] == rei.INDEX_FORMAT
    assert generated["visual_only"] is True
    assert generated["promotion_authorized_by_index"] is False

    zones = [entry["zone"] for entry in generated["entries"]]
    paths = [entry["data_path"] for entry in generated["entries"]]
    assert zones == ["jette", "midi"]
    assert zones == sorted(zones)
    assert len(paths) == len(set(paths))

    jette = next(row for row in generated["entries"] if row["zone"] == "jette")
    assert jette["data_path"] == "res://data/osm/zones/jette/environment.game.json"
    assert jette["artifact_format"] == rei.ARTIFACT_FORMAT
    assert jette["bounds_m"] == [-2969.44, -5761.07, -168.12, -3460.32]
    assert jette["stats"] == {"tree": 3832, "street_lamp": 603, "bollard": 149, "total": 4584}

    midi = next(row for row in generated["entries"] if row["zone"] == "midi")
    assert midi["data_path"] == "res://data/osm/zones/midi/environment.game.json"
    assert midi["artifact_format"] == rei.ARTIFACT_FORMAT
    assert midi["bounds_m"] == [-617.36, -711.26, 631.74, 638.94]
    assert midi["stats"] == {"tree": 1694, "street_lamp": 104, "bollard": 732, "total": 2530}

    artifact = rei.read_json(PROJECT / "data/osm/zones/jette/environment.game.json")
    bad_license = dict(artifact)
    bad_license["license"] = "invalid"
    try:
        rei.validate_artifact("jette", bad_license)
    except rei.EnvironmentIndexError:
        pass
    else:
        raise AssertionError("bad environment license must fail closed")

    module = json.loads(MODULE.read_text(encoding="utf-8"))
    assert module == {
        "schema": "grand-bruxelles-runtime-module-v1",
        "enabled": True,
        "name": "CityMachineEnvironmentRuntime",
        "path": "res://game/scripts/brussels_city_machine_environment_runtime.gd",
    }

    bridge = BRIDGE.read_text(encoding="utf-8")
    assert "runtime_environment_index.json" in bridge
    assert "promotion_authorized_by_index" in bridge
    assert "visual_only" in bridge
    assert "activation_margin_m" in bridge and "unload_margin_m" in bridge
    assert "RENDERER_SCRIPT.new()" in bridge
    assert "DirAccess" not in bridge

    renderer = RENDERER.read_text(encoding="utf-8")
    assert 'SOURCE_FORMAT := "grand-bruxelles-osm-zone-environment-v1"' in renderer
    assert 'SUPPORTED_KINDS := ["tree", "street_lamp", "bollard"]' in renderer

    assert rei.build_index() == generated
    print("RUNTIME_ENVIRONMENT_INDEX_TEST_OK deterministic=true indexed_zones=2 jette_points=4584 midi_points=2530 visual_only=true no_runtime_scan=true fail_closed=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
