#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]


def main() -> int:
    registry = json.loads((HERE / "registry.json").read_text(encoding="utf-8"))
    assert registry["schema"] == "grand-bruxelles-city-machine-registry-v1"
    assert registry["pilot_zone"] == "jette"
    assert set(registry["zone_profiles"]) == {"jette"}

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
    assert {"G1_sources_crs", "G2_spawn_ground", "G3_buildings_streets"} <= gates
    assert [row["slug"] for row in layers if row["kind"] == "materialize_geojson"] == [
        "buildings", "street_surfaces", "street_axes", "train_network"
    ]

    inventory = registry["tool_inventory"]
    assert len(inventory["citygen"]) == 19
    assert len(inventory["city_generation"]) == 5
    for name in inventory["citygen"]:
        assert (PROJECT / "tools/citygen" / name).is_file(), name
    for name in inventory["city_generation"]:
        assert (PROJECT / "tools/city_generation" / name).is_file(), name

    print(f"CITY_MACHINE_REGISTRY_OK layers={len(layers)} citygen=19 city_generation=5 pilot=jette all_scripts_real=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
