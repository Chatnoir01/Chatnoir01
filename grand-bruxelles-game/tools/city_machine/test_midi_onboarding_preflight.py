#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
SCRIPT = HERE / "check_onboarding_candidate.py"


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "midi-preflight.json"
        run = subprocess.run(
            [sys.executable, str(SCRIPT), "--zone", "midi", "--output", str(output)],
            cwd=PROJECT,
            text=True,
            capture_output=True,
        )
        assert run.returncode == 2, (run.returncode, run.stdout, run.stderr)
        report = json.loads(output.read_text(encoding="utf-8"))

    assert report["zone"] == "midi"
    assert report["eligible"] is False
    assert report["result"] == "BLOCKED_FAIL_CLOSED"
    assert report["promotion_performed"] is False

    checks = {row["id"]: row for row in report["checks"]}
    assert checks["source_crs"]["status"] == "PASS"
    assert checks["city_machine_source_contract"]["status"] == "PASS"
    assert checks["catalog_arrival_contract"]["status"] == "PASS"
    assert checks["runtime_arrival_pose"]["status"] == "PASS"
    assert checks["regional_osm_cache"]["status"] == "PASS"
    assert checks["regional_osm_runtime"]["status"] == "PASS"
    assert checks["partial_slice_rejected"]["status"] == "PASS"
    assert checks["runtime_consumes_city_machine_outputs"]["status"] == "FAIL"
    assert set(report["failed_checks"]) == {"runtime_consumes_city_machine_outputs"}

    candidates = json.loads((HERE / "onboarding_candidates.json").read_text(encoding="utf-8"))
    midi = candidates["candidates"]["midi"]
    partial = json.loads((PROJECT / midi["regional_osm"]["forbidden_partial_substitute"]).read_text(encoding="utf-8"))
    assert partial["corridor"]["name"] == "Midi -> Anneessens -> Bourse -> Grand-Place"
    assert int(partial["stats"]["roads"]) < int(partial["source_stats"]["roads"])

    registry = json.loads((HERE / "registry.json").read_text(encoding="utf-8"))
    assert "midi" not in registry["zone_profiles"], "blocked candidate must never become an executable profile"

    print("CITY_MACHINE_MIDI_PREFLIGHT_OK eligible=false fail_closed=true crs=true arrival=true full_osm=true runtime_wiring=false partial_slice_rejected=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
