#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

REQUIRED_RUNTIME_CONSTANTS = (
    "MAX_OBSERVED_SPEED_MPS",
    "RUN_ENTER_SPEED_MPS",
    "RUN_REFERENCE_SPEED_MPS",
    "RUN_PLAYBACK_MIN",
    "RUN_PLAYBACK_MAX",
)


def parse_runtime_constants(text: str) -> dict[str, float]:
    values: dict[str, float] = {}
    for name in REQUIRED_RUNTIME_CONSTANTS:
        match = re.search(rf"^const\s+{re.escape(name)}\s*:=\s*([0-9]+(?:\.[0-9]+)?)\s*$", text, re.MULTILINE)
        if match is None:
            raise ValueError(f"missing_runtime_constant:{name}")
        values[name] = float(match.group(1))
    return values


def evaluate_clip(required_root_mean_mps: float, runtime: dict[str, float]) -> dict[str, Any]:
    if not math.isfinite(required_root_mean_mps) or required_root_mean_mps <= 0.0:
        raise ValueError("invalid_required_root_speed")
    run_enter = runtime["RUN_ENTER_SPEED_MPS"]
    max_world = runtime["MAX_OBSERVED_SPEED_MPS"]
    playback_min = runtime["RUN_PLAYBACK_MIN"]
    playback_max = runtime["RUN_PLAYBACK_MAX"]
    run_reference = runtime["RUN_REFERENCE_SPEED_MPS"]
    if not (0.0 < run_enter <= run_reference <= max_world):
        raise ValueError("invalid_runtime_speed_interval")
    if not (0.0 < playback_min <= playback_max):
        raise ValueError("invalid_playback_interval")

    planted_min = required_root_mean_mps * playback_min
    planted_max = required_root_mean_mps * playback_max
    overlap_min = max(run_enter, planted_min)
    overlap_max = min(max_world, planted_max)
    compatible = overlap_min <= overlap_max + 1e-9

    return {
        "required_root_speed_mean_mps_at_1x": required_root_mean_mps,
        "runtime_run_speed_interval_mps": [run_enter, max_world],
        "planted_speed_interval_at_allowed_playback_mps": [planted_min, planted_max],
        "ideal_playback_at_run_reference": run_reference / required_root_mean_mps,
        "ideal_playback_at_runtime_max_speed": max_world / required_root_mean_mps,
        "minimum_world_speed_for_planted_feet_mps": planted_min,
        "speed_excess_over_runtime_max_at_min_playback_mps": planted_min - max_world,
        "interval_overlap_mps": None if not compatible else [overlap_min, overlap_max],
        "compatible_with_current_civilian_run_contract": compatible,
        "verdict": "COMPATIBLE_CURRENT_CIVILIAN_RUN_CONTRACT" if compatible else "JETER_CURRENT_CIVILIAN_RUN_CONTRACT",
    }


def evaluate(manifest: dict[str, Any], runtime_text: str) -> dict[str, Any]:
    runtime = parse_runtime_constants(runtime_text)
    expected = manifest["runtime_contract"]["expected"]
    for name in REQUIRED_RUNTIME_CONSTANTS:
        if abs(runtime[name] - float(expected[name])) > 1e-9:
            raise ValueError(f"runtime_contract_drift:{name}:{runtime[name]}:{expected[name]}")

    proof = manifest["root_compensation_proof"]
    clips: dict[str, Any] = {}
    for clip, speed in proof["required_root_speed_mean_mps"].items():
        clips[clip] = evaluate_clip(float(speed), runtime)

    compatible_count = sum(1 for row in clips.values() if row["compatible_with_current_civilian_run_contract"])
    state = "CURRENT_CIVILIAN_SPEED_CONTRACT_COMPATIBLE" if compatible_count else "CURRENT_CIVILIAN_SPEED_CONTRACT_INCOMPATIBLE"
    return {
        "format": "grand-bruxelles-gate8-variant01-run-speed-contract-compatibility-result-v1",
        "candidate_variant": manifest["candidate_variant"],
        "runtime_contract": runtime,
        "root_compensation_run_id": proof["run_id"],
        "root_compensation_artifact_id": proof["artifact_id"],
        "root_compensation_artifact_digest": proof["artifact_digest"],
        "clips": clips,
        "compatible_clip_count": compatible_count,
        "decision_state": state,
        "run_alias_selected": "",
        "root_motion_applied": False,
        "production_authorized": False,
        "activation_ready": False,
        "adoption_ready": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    manifest = json.loads(Path(args.manifest).read_text())
    result = evaluate(manifest, Path(args.runtime).read_text())
    expected = manifest["expected_decision"]
    if result["decision_state"] != expected["state"]:
        raise SystemExit(f"unexpected_decision_state:{result['decision_state']}")
    if result["compatible_clip_count"] != int(expected["compatible_clip_count"]):
        raise SystemExit(f"unexpected_compatible_count:{result['compatible_clip_count']}")
    for clip, row in result["clips"].items():
        if row["verdict"] != expected["clip_verdict"]:
            raise SystemExit(f"unexpected_clip_verdict:{clip}:{row['verdict']}")

    Path(args.output).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(
        "GATE8_RUN_SPEED_CONTRACT state=%s compatible=%d clips=%s production_authorized=false"
        % (result["decision_state"], result["compatible_clip_count"], ",".join(sorted(result["clips"])))
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
