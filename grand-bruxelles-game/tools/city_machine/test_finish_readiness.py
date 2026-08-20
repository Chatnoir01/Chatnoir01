#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys

import finish_readiness as readiness


def main() -> int:
    assert readiness.PRODUCTION_GATES == [
        "G7_generated_ownership",
        "G8_landmark_non_regression",
        "G9_collision_solidity",
        "G10_geometry_outliers",
        "G11_streaming_mount",
        "G12_performance_evidence",
    ]

    audit = subprocess.run(
        [sys.executable, str(readiness.__file__), "--zone", "jette"],
        cwd=readiness.cm.PROJECT,
        text=True,
        capture_output=True,
    )
    assert audit.returncode == 0, audit.stderr
    log = audit.stdout + audit.stderr
    assert "CITY_MACHINE_READINESS PASS G7_generated_ownership" in log
    assert "CITY_MACHINE_READINESS PASS G8_landmark_non_regression" in log
    assert "CITY_MACHINE_READINESS BLOCKED G9_collision_solidity" in log
    assert "CITY_MACHINE_READINESS PASS G10_geometry_outliers" in log
    assert "CITY_MACHINE_READINESS BLOCKED G11_streaming_mount" in log
    assert "CITY_MACHINE_READINESS BLOCKED G12_performance_evidence" in log
    assert "promotion=blocked" in log

    strict = subprocess.run(
        [sys.executable, str(readiness.__file__), "--zone", "jette", "--require-ready"],
        cwd=readiness.cm.PROJECT,
        text=True,
        capture_output=True,
    )
    assert strict.returncode == 4, (strict.returncode, strict.stdout, strict.stderr)

    print("CITY_MACHINE_READINESS_TESTS_OK gates=6 pass=3 blocked=3 require_ready_exit=4 auto_promotion=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
