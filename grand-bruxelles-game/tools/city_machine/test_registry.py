#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]


def main() -> int:
    registry = json.loads((HERE / "registry.json").read_text(encoding="utf-8"))
    assert registry["schema"] == "grand-bruxelles-city-machine-registry-v1"
    assert registry["version"] == 4
    assert registry["pilot_zone"] == "jette"
    assert "jette" in registry["zone_profiles"]

    for zone_id, profile in registry["zone_profiles"].items():
        assert (PROJECT / profile["source_root"]).is_dir(), zone_id
        assert (PROJECT / profile["validator_script"]).is_file(), zone_id
        assert (PROJECT / profile["runtime_script"]).is_file(), zone_id
        assert profile["materialized_slugs"] == ["buildings", "street_surfaces", "street_axes", "train_network"]
        assert profile["content_minimums"]["buildings"] >= 1
        assert profile["content_minimums"]["street_surfaces"] >= 1

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
        else:
            assert row["enabled_zones"] == ["*"], row["layer_id"]

    gates = {row["gate"] for row in layers if row.get("gate")}
    assert {"G1_sources_crs", "G2_spawn_ground", "G3_buildings_streets", "G4_runtime_finish", "G5_osm_environment"} <= gates
    assert [row["slug"] for row in layers if row["kind"] == "materialize_geojson"] == ["buildings", "street_surfaces", "street_axes", "train_network"]

    osm = next(row for row in layers if row["layer_id"] == "osm_environment_points")
    assert osm["kind"] == "materialize_osm_environment" and osm["enabled_zones"] == ["*"]
    assert osm["inputs"] == ["profile:osm_environment.cache", "profile:source_root/manifest.json"]

    runtime_index = next(row for row in layers if row["layer_id"] == "runtime_environment_index")
    assert runtime_index["kind"] == "materialize_runtime_environment_index"
    assert runtime_index["outputs"] == ["data/runtime/runtime_environment_index.json"]
    assert runtime_index["enabled_zones"] == ["*"]
    assert (PROJECT / runtime_index["outputs"][0]).is_file()

    jette = registry["zone_profiles"]["jette"]
    env = jette["osm_environment"]
    assert env["minimum_trees"] >= 1 and 0.0 < float(env["bounds_tolerance_m"]) <= 2.0
    for key in ("cache", "runtime"):
        assert (PROJECT / env[key]).is_file(), env[key]

    live = next(row for row in layers if row["layer_id"] == "live_osm_environment_refresh")
    assert live["kind"] == "disabled" and not live["enabled_zones"] and live["disabled_reason"]

    inventory = registry["tool_inventory"]
    assert len(inventory["citygen"]) == 19 and len(inventory["city_generation"]) == 5
    for name in inventory["citygen"]: assert (PROJECT / "tools/citygen" / name).is_file(), name
    for name in inventory["city_generation"]: assert (PROJECT / "tools/city_generation" / name).is_file(), name
    assert "tools/city_machine/build_runtime_environment_index.py" in inventory["osm_environment"]

    print(f"CITY_MACHINE_REGISTRY_OK version=4 layers={len(layers)} profiles={len(registry['zone_profiles'])} regional_onboarding=generic wildcard_layers=true all_scripts_real=true")
    return 0


if __name__ == "__main__": raise SystemExit(main())
