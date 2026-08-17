#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys

import finish_environment_stage as stage


def main() -> int:
    result = subprocess.run(
        [sys.executable, str(stage.__file__), "--zone", "jette", "--dry-run"],
        cwd=stage.cm.PROJECT,
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    log = result.stdout + result.stderr
    assert "CITY_MACHINE_FAMILY START osm_environment zone=jette" in log
    assert "CITY_MACHINE_LAYER START osm_environment_points" in log
    assert "CITY_MACHINE_LAYER END osm_environment_points" in log
    assert "materialize_buildings_runtime" not in log
    assert "finish_materials" not in log
    assert "life" not in log

    bad = subprocess.run(
        [sys.executable, str(stage.__file__), "--zone", "midi", "--dry-run"],
        cwd=stage.cm.PROJECT,
        text=True,
        capture_output=True,
    )
    assert bad.returncode != 0
    print("CITY_MACHINE_ENV_TESTS_OK jette_osm_only=true geometry_not_run=true fail_closed=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
