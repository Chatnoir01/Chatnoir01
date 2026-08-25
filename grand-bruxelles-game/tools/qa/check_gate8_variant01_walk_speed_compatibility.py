#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

REQUIRED_RUNTIME_CONSTANTS = (
    "IDLE_EXIT_SPEED_MPS",
    "RUN_ENTER_SPEED_MPS",
    "WALK_REFERENCE_SPEED_MPS",
    "WALK_PLAYBACK_MIN",
    "WALK_PLAYBACK_MAX",
)


def parse_runtime_constants(text: str) -> dict[str, float]:
    values: dict[str, float] = {}
    for name in REQUIRED_RUNTIME_CONSTANTS:
        match = re.search(rf"^const\s+{re.escape(name)}\s*:=\s*([0-9]+(?:\.[0-9]+)?)\s*$", text, re.MULTILINE)
        if match is None:
            raise ValueError(f"missing_runtime_constant:{name}")
        values[name] = float(match.group(1))
    return values


def evaluate_clip(name: str, required_root_mean_mps: float, runtime: dict[str, float], semantic_role: str) -> dict[str, Any]:
    if not math.isfinite(required_root_mean_mps) or required_root_mean_mps <= 0.0:
        raise ValueError("invalid_required_root_speed")
    walk_min = runtime["IDLE_EXIT_SPEED_MPS"]
    walk_max = runtime["RUN_ENTER_SPEED_MPS"]
    reference = runtime["WALK_REFERENCE_SPEED_MPS"]
    playback_min = runtime["WALK_PLAYBACK_MIN"]
    playback_max = runtime["WALK_PLAYBACK_MAX"]
    if not (0.0 <= walk_min < reference < walk_max):
        raise ValueError("invalid_walk_speed_interval")
    if not (0.0 < playback_min <= 1.0 <= playback_max):
        raise ValueError("invalid_walk_playback_interval")

    planted_min = required_root_mean_mps * playback_min
    planted_max = required_root_mean_mps * playback_max
    overlap_min = max(walk_min, planted_min)
    overlap_max = min(walk_max, planted_max)
    overlap = overlap_min <= overlap_max + 1e-9
    ideal_playback = reference / required_root_mean_mps
    reference_reachable = playback_min - 1e-9 <= ideal_playback <= playback_max + 1e-9
    semantic_ok = semantic_role == "normal_walk"
    compatible = overlap and reference_reachable and semantic_ok
    return {
        "required_root_speed_mean_mps_at_1x": required_root_mean_mps,
        "semantic_role": semantic_role,
        "runtime_walk_speed_interval_mps": [walk_min, walk_max],
        "planted_speed_interval_at_allowed_playback_mps": [planted_min, planted_max],
        "interval_overlap_mps": [overlap_min, overlap_max] if overlap else None,
        "ideal_playback_at_walk_reference": ideal_playback,
        "walk_reference_reachable_with_allowed_playback": reference_reachable,
        "semantic_role_allowed_for_normal_walk": semantic_ok,
        "compatible_with_current_civilian_walk_speed_contract": compatible,
        "verdict": "WALK_SPEED_COMPATIBLE_PENDING_GROUNDING_TORSO" if compatible else "JETER_CURRENT_NORMAL_WALK_CONTRACT",
    }


def evaluate(manifest: dict[str, Any], runtime_text: str) -> dict[str, Any]:
    runtime = parse_runtime_constants(runtime_text)
    expected = manifest["runtime_contract"]["expected"]
    for name in REQUIRED_RUNTIME_CONSTANTS:
        if abs(runtime[name] - float(expected[name])) > 1e-9:
            raise ValueError(f"runtime_contract_drift:{name}:{runtime[name]}:{expected[name]}")
    proof = manifest["source_scan_proof"]
    roles = manifest["semantic_roles"]
    clips: dict[str, Any] = {}
    for clip, speed in proof["required_root_speed_mean_mps"].items():
        if clip not in roles:
            raise ValueError(f"missing_semantic_role:{clip}")
        row = evaluate_clip(clip, float(speed), runtime, str(roles[clip]))
        row["contact_slide_peak_mps_at_1x"] = float(proof["contact_slide_peak_mps"][clip])
        clips[clip] = row
    compatible = [name for name, row in clips.items() if row["compatible_with_current_civilian_walk_speed_contract"]]
    rejected = [name for name, row in clips.items() if not row["compatible_with_current_civilian_walk_speed_contract"]]
    return {
        "format": "grand-bruxelles-gate8-variant01-walk-speed-contract-compatibility-result-v1",
        "candidate_variant": manifest["candidate_variant"],
        "runtime_contract": runtime,
        "source_scan_run_id": proof["run_id"],
        "source_scan_artifact_id": proof["artifact_id"],
        "source_scan_artifact_digest": proof["artifact_digest"],
        "clips": clips,
        "compatible_normal_walk_candidates": compatible,
        "rejected_normal_walk_candidates": rejected,
        "decision_state": "WALK_SPEED_COMPATIBLE_PENDING_GROUNDING_TORSO" if compatible else "NO_COMPATIBLE_NORMAL_WALK_SPEED_CANDIDATE",
        "walk_alias_selected": "",
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
    if result["compatible_normal_walk_candidates"] != expected["compatible_normal_walk_candidates"]:
        raise SystemExit(f"unexpected_compatible_candidates:{result['compatible_normal_walk_candidates']}")
    if result["rejected_normal_walk_candidates"] != expected["rejected_normal_walk_candidates"]:
        raise SystemExit(f"unexpected_rejected_candidates:{result['rejected_normal_walk_candidates']}")
    Path(args.output).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print("GATE8_WALK_SPEED_CONTRACT state=%s compatible=%s rejected=%s alias_selected=false production_authorized=false" % (
        result["decision_state"], ",".join(result["compatible_normal_walk_candidates"]), ",".join(result["rejected_normal_walk_candidates"])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
