#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys

import finish_geometry_stage as stage


def main() -> int:
    assert stage.GEOMETRY_KINDS == {"resolve_zone", "materialize_geojson"}
    assert stage.GEOMETRY_GATES == {"G1_sources_crs", "G2_spawn_ground", "G3_buildings_streets"}

    result = subprocess.run(
        [sys.executable, str(stage.__file__), "--zone", "jette", "--dry-run"],
        cwd=stage.cm.PROJECT,
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    log = result.stdout + result.stderr
    for layer in (
        "resolve_catalog_zone",
        "materialize_buildings_runtime",
        "materialize_street_surfaces_runtime",
        "materialize_street_axes_runtime",
        "materialize_train_network_runtime",
    ):
        assert f"CITY_MACHINE_LAYER START {layer}" in log
        assert f"CITY_MACHINE_LAYER END {layer}" in log
    assert "osm_environment_points" not in log
    assert "finish_materials" not in log
    assert "CITY_MACHINE_FAMILY END geometry" in log

    bad = subprocess.run(
        [sys.executable, str(stage.__file__), "--zone", "midi", "--dry-run"],
        cwd=stage.cm.PROJECT,
        text=True,
        capture_output=True,
    )
    assert bad.returncode != 0
    print("CITY_MACHINE_GEOMETRY_TESTS_OK jette_only=true geometry_layers=5 osm_not_run=true fail_closed=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
