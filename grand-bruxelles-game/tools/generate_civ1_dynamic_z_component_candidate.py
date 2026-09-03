#!/usr/bin/env python3
"""Generate a QA-only time-varying CIV-1 RightFoot Z-component blend schedule.

This family is deliberately different from the rejected local-X/local-Z rotation families.
It blends only the target-local RightFoot rest Z component toward the previously causal
source-derived Z component, while the native probe preserves X and total foot-rest length.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

CENTER_SAMPLE = 59
CYCLE_SAMPLE_COUNT = 120
CANDIDATE_KIND = "civ1_rightfoot_dynamic_z_component_schedule"
COMPONENT = "target_local_rest_z"


def generate(radius_samples: int, peak_blend: float) -> dict:
    if isinstance(radius_samples, bool) or not isinstance(radius_samples, int):
        raise ValueError("radius_samples must be an integer")
    if radius_samples < 2 or radius_samples >= CYCLE_SAMPLE_COUNT // 2:
        raise ValueError("radius_samples must be in [2, 59]")
    if isinstance(peak_blend, bool) or not isinstance(peak_blend, (int, float)):
        raise ValueError("peak_blend must be numeric")
    peak = float(peak_blend)
    if not math.isfinite(peak) or not 0.0 < peak <= 1.0:
        raise ValueError("peak_blend must be finite and in (0, 1]")

    samples = []
    for index in range(CYCLE_SAMPLE_COUNT):
        distance = min(
            (index - CENTER_SAMPLE) % CYCLE_SAMPLE_COUNT,
            (CENTER_SAMPLE - index) % CYCLE_SAMPLE_COUNT,
        )
        blend = 0.0
        if distance <= radius_samples:
            blend = peak * 0.5 * (1.0 + math.cos(math.pi * distance / (radius_samples + 1)))
        samples.append({
            "z_component_blend": blend,
            "right_foot_length_error_m": 0.0,
            "left_foot_delta_m": 0.0,
        })

    return {
        "candidate_kind": CANDIDATE_KIND,
        "component": COMPONENT,
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
    parser.add_argument("--peak-blend", type=float, required=True)
    args = parser.parse_args()
    payload = generate(args.radius_samples, args.peak_blend)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
