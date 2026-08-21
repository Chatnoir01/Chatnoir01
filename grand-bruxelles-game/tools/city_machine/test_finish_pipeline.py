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
        "finish_materials": "wired",
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
        "CITY_MACHINE_FAMILY START finish_materials zone=jette",
        "CITY_MACHINE_FAMILY SKIP life status=disabled",
        "CITY_MACHINE_FAMILY START proof zone=jette",
        "CITY_MACHINE_READINESS_START zone=jette require_ready=false",
    ]
    positions = [log.index(marker) for marker in markers]
    assert positions == sorted(positions), positions
    assert "CITY_MACHINE_GATE PASS G6_finish_materials" in log
    assert "CITY_MACHINE_READINESS PASS G7_generated_ownership" in log
    assert "CITY_MACHINE_READINESS PASS G8_landmark_non_regression" in log
    assert "CITY_MACHINE_READINESS BLOCKED G9_collision_solidity" in log
    assert "CITY_MACHINE_READINESS PASS G10_geometry_outliers" in log
    assert "CITY_MACHINE_READINESS BLOCKED G11_streaming_mount" in log
    assert "CITY_MACHINE_READINESS BLOCKED G12_performance_evidence" in log
    assert "CITY_MACHINE_LAYER SKIP facade_candidate_pipeline" in log
    assert "CITY_MACHINE_FINISH_END zone=jette result=LABO_DATA_READY promotion=false" in log

    strict = subprocess.run(
        [sys.executable, str(fp.HERE / "finish_pipeline.py"), "build", "--zone", "jette", "--dry-run", "--require-ready"],
        cwd=fp.PROJECT,
        text=True,
        capture_output=True,
    )
    assert strict.returncode == 4, (strict.returncode, strict.stdout, strict.stderr)
    assert "stage=finish_readiness.py rc=4" in strict.stderr

    bad = subprocess.run(
        [sys.executable, str(fp.HERE / "finish_pipeline.py"), "build", "--zone", "midi", "--dry-run"],
        cwd=fp.PROJECT,
        text=True,
        capture_output=True,
    )
    assert bad.returncode != 0
    assert "pilot locked to jette" in bad.stderr

    print("CITY_MACHINE_FINISH_TESTS_OK pilot=jette strict_order=true materials_wired=true g6=true g7_g12_audited=true promotion_guard=true auto_jouable=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
