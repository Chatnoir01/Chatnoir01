#!/usr/bin/env python3
"""Generate a structural CIV-1 RightFoot rotation schedule for native measurement.

The output is candidate input only. It does not claim that the rotation has been
applied by Godot, measured in player view, or approved for runtime.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

CENTER_SAMPLE = 59
CYCLE_SAMPLE_COUNT = 120


def generate(radius_samples: int, peak_rotation_rad: float) -> dict:
    if isinstance(radius_samples, bool) or not isinstance(radius_samples, int):
        raise ValueError("radius_samples must be an integer")
    if radius_samples < 2 or radius_samples >= CYCLE_SAMPLE_COUNT // 2:
        raise ValueError("radius_samples must be in [2, 59]")
    if isinstance(peak_rotation_rad, bool) or not isinstance(peak_rotation_rad, (int, float)):
        raise ValueError("peak_rotation_rad must be numeric")
    peak = float(peak_rotation_rad)
    if not math.isfinite(peak) or abs(peak) <= 1e-9 or abs(peak) > math.pi / 2:
        raise ValueError("peak_rotation_rad must be finite, nonzero and <= pi/2")

    samples = []
    for i in range(CYCLE_SAMPLE_COUNT):
        distance = min((i - CENTER_SAMPLE) % CYCLE_SAMPLE_COUNT, (CENTER_SAMPLE - i) % CYCLE_SAMPLE_COUNT)
        angle = 0.0
        if distance <= radius_samples:
            # Raised-cosine taper stays non-zero at the declared edge while strictly
            # decreasing away from the measured plant center.
            weight = 0.5 * (1.0 + math.cos(math.pi * distance / (radius_samples + 1)))
            angle = peak * weight
        samples.append({
            "rotation_delta_rad": angle,
            "right_foot_length_error_m": 0.0,
            "left_foot_delta_m": 0.0,
        })

    return {
        "candidate_kind": "civ1_rightfoot_dynamic_rotation_schedule",
        "candidate_is_native_measurement": False,
        "center_sample": CENTER_SAMPLE,
        "radius_samples": radius_samples,
        "cycle_sample_count": CYCLE_SAMPLE_COUNT,
        "baseline_source_plant_sample": CENTER_SAMPLE,
        "baseline_cycle_sample_count": CYCLE_SAMPLE_COUNT,
        "samples": samples,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--radius-samples", type=int, required=True)
    parser.add_argument("--peak-rotation-rad", type=float, required=True)
    args = parser.parse_args()
    payload = generate(args.radius_samples, args.peak_rotation_rad)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
