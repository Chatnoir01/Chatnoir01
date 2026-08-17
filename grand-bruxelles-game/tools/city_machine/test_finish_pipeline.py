#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys

import finish_pipeline as fp


def main() -> int:
    reg = fp.validate_finish_registry("jette")
    assert [row["family_id"] for row in reg["families"]] == fp.EXPECTED_FAMILIES
    assert reg["auto_jouable"] is False
    assert {row["family_id"]: row["status"] for row in reg["families"]} == {
        "geometry": "wired",
        "osm_environment": "wired",
        "finish_materials": "missing",
        "life": "disabled",
        "proof": "wired",
    }

    result = subprocess.run(
        [sys.executable, str(fp.HERE / "finish_pipeline.py"), "build", "--zone", "jette", "--dry-run"],
        cwd=fp.PROJECT,
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    log = result.stdout + result.stderr
    markers = [
        "CITY_MACHINE_FAMILY START geometry zone=jette",
        "CITY_MACHINE_FAMILY START osm_environment zone=jette",
        "CITY_MACHINE_FAMILY SKIP finish_materials status=missing",
        "CITY_MACHINE_FAMILY SKIP life status=disabled",
        "CITY_MACHINE_FAMILY START proof zone=jette",
    ]
    positions = [log.index(marker) for marker in markers]
    assert positions == sorted(positions), positions
    assert "CITY_MACHINE_LAYER SKIP facade_candidate_pipeline" in log
    assert "CITY_MACHINE_FINISH_END zone=jette result=LABO_DATA_READY promotion=false" in log

    bad = subprocess.run(
        [sys.executable, str(fp.HERE / "finish_pipeline.py"), "build", "--zone", "midi", "--dry-run"],
        cwd=fp.PROJECT,
        text=True,
        capture_output=True,
    )
    assert bad.returncode != 0
    assert "pilot locked to jette" in bad.stderr

    print("CITY_MACHINE_FINISH_TESTS_OK pilot=jette strict_order=true skips_visible=true fail_closed=true auto_jouable=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
