#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import check_onboarding_candidate as preflight

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
        assert run.returncode == 0, (run.returncode, run.stdout, run.stderr)
        report = json.loads(output.read_text(encoding="utf-8"))

    assert report["zone"] == "midi"
    assert report["eligible"] is True
    assert report["result"] == "READY_FOR_PROFILE"
    assert report["promotion_performed"] is False
    assert report["failed_checks"] == []

    checks = {row["id"]: row for row in report["checks"]}
    for check_id in (
        "source_crs",
        "execution_source_contract",
        "catalog_arrival_contract",
        "runtime_arrival_pose",
        "regional_osm_cache",
        "regional_osm_runtime",
        "regional_osm_cache_contract",
        "regional_osm_runtime_contract",
        "regional_osm_digest",
        "regional_osm_points_contract",
        "partial_slice_rejected",
    ):
        assert checks[check_id]["status"] == "PASS", (check_id, checks[check_id])

    candidates = json.loads((HERE / "onboarding_candidates.json").read_text(encoding="utf-8"))
    midi = candidates["candidates"]["midi"]
    partial = json.loads((PROJECT / midi["regional_osm"]["forbidden_partial_substitute"]).read_text(encoding="utf-8"))
    assert partial["corridor"]["name"] == "Midi -> Anneessens -> Bourse -> Grand-Place"
    assert int(partial["stats"]["roads"]) < int(partial["source_stats"]["roads"])

    registry = json.loads((HERE / "registry.json").read_text(encoding="utf-8"))
    assert "midi" in registry["zone_profiles"]
    assert registry["zone_profiles"]["midi"]["arrival_contract"]["destination"] == "midi"

    cache_path = PROJECT / midi["regional_osm"]["required_cache"]
    runtime_path = PROJECT / midi["regional_osm"]["required_runtime"]
    runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    runtime["source_digest"] = "0" * 64
    with tempfile.TemporaryDirectory() as tmp:
        tampered_path = Path(tmp) / "environment.game.json"
        tampered_path.write_text(json.dumps(runtime), encoding="utf-8")
        tampered_checks = {
            row["id"]: row
            for row in preflight.validate_regional_osm("midi", midi, cache_path, tampered_path)
        }
    assert tampered_checks["regional_osm_digest"]["status"] == "FAIL"

    # Fail-closed regression: an incomplete City Machine execution manifest must
    # never raise KeyError from game_bounds(). The caller must be able to turn
    # missing/invalid origin metadata into an ordinary BLOCKED check result.
    assert preflight.game_bounds({"bbox": [147250, 168900, 148500, 170250]}) is None
    assert preflight.game_bounds({
        "bbox": [147250, 168900, 148500, 170250],
        "game_origin": {"e": 148400},
    }) is None

    print("CITY_MACHINE_MIDI_PREFLIGHT_OK eligible=true crs=true arrival=true full_osm=true partial_slice_rejected=true tampered_digest_rejected=true missing_game_origin_fail_closed=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())