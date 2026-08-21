#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]


def main() -> int:
    registry = json.loads((HERE / "registry.json").read_text(encoding="utf-8"))
    assert registry["schema"] == "grand-bruxelles-city-machine-registry-v1"
    assert registry["version"] == 3
    assert registry["pilot_zone"] == "jette"
    assert set(registry["zone_profiles"]) == {"jette"}
    assert registry["generator_inventory"] == "tools/city_machine/generator_inventory.json"

    profile = registry["zone_profiles"]["jette"]
    assert profile["zone_id"] == "jette"
    assert profile["crs"] == "EPSG:31370"
    assert (PROJECT / profile["runtime_script"]).is_file()
    assert (PROJECT / profile["runtime_scene"]).is_file()
    assert set(profile["available_layers"]) >= {"buildings", "street_surfaces", "street_axes", "tram_network", "train_network", "osm_environment"}
    assert profile["streaming"]["status"] == "contract_only"
    assert profile["streaming"]["runtime_mount_authorized"] is False
    assert profile["finish_materials"]["output"] == "data/runtime/city_machine/jette/finish_materials.game.json"

    layers = registry["layers"]
    orders = [int(row["order"]) for row in layers]
    assert orders == sorted(orders) and len(orders) == len(set(orders))
    assert len({row["layer_id"] for row in layers}) == len(layers)
    for row in layers:
        assert {"layer_id", "script", "inputs", "outputs", "gate", "enabled_zones"} <= set(row)
        assert (PROJECT / row["script"]).is_file(), row["script"]
        assert "implementation" not in row
        if row["kind"] == "disabled":
            assert not row["enabled_zones"] and row.get("disabled_reason")

    gates = {row["gate"] for row in layers if row.get("gate")}
    assert {"G1_sources_crs", "G2_spawn_ground", "G3_buildings_streets", "G4_runtime_finish", "G5_osm_environment"} <= gates
    assert [row["slug"] for row in layers if row["kind"] == "materialize_geojson"] == [
        "buildings", "street_surfaces", "street_axes", "tram_network", "train_network"
    ]
    tram = next(row for row in layers if row["layer_id"] == "materialize_tram_network_runtime")
    assert tram["enabled_zones"] == ["jette"] and tram["slug"] == "tram_network"
    osm = next(row for row in layers if row["layer_id"] == "osm_environment_points")
    assert osm["kind"] == "materialize_osm_environment" and osm["enabled_zones"] == ["jette"]
    env = profile["osm_environment"]
    assert env["minimum_trees"] >= 1 and 0.0 < float(env["bounds_tolerance_m"]) <= 2.0
    for key in ("cache", "runtime"):
        assert (PROJECT / env[key]).is_file(), env[key]
    live = next(row for row in layers if row["layer_id"] == "live_osm_environment_refresh")
    assert live["kind"] == "disabled" and not live["enabled_zones"] and live["disabled_reason"]

    inventory = registry["tool_inventory"]
    assert len(inventory["citygen"]) == 19 and len(inventory["city_generation"]) == 5
    for name in inventory["citygen"]:
        assert (PROJECT / "tools/citygen" / name).is_file(), name
    for name in inventory["city_generation"]:
        assert (PROJECT / "tools/city_generation" / name).is_file(), name
    assert "build_osm_environment_zone.py" not in inventory["osm_environment_support"]
    assert "build_osm_environment_zone.py" in inventory["city_machine"]
    assert "finish_materials.py" in inventory["city_machine"]
    assert "finish_materials_stage.py" in inventory["city_machine"]

    canonical = json.loads((PROJECT / registry["generator_inventory"]).read_text(encoding="utf-8"))
    assert canonical["unique_generators_before_lot"] == 39
    assert canonical["unique_generators_after_lot"] == 41
    assert len(canonical["generators"]) == 41
    assert len({row["path"] for row in canonical["generators"]}) == 41

    print(f"CITY_MACHINE_REGISTRY_OK version=3 layers={len(layers)} pilot=jette tram=rebuild materials=profiled generator_inventory=41")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
