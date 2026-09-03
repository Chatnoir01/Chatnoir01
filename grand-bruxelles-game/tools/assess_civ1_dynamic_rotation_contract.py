#!/usr/bin/env python3
"""Fail-closed contract for CIV-1 time-varying RightFoot rotation candidates.

This gate does not authorize runtime or visual approval. It binds candidates to the
measured native CIV-1 source plant/cycle before native phase/grounding assessment.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

BLOCK = "BLOCK_DYNAMIC_ROTATION_CONTRACT"
ALLOW = "REQUIRE_NATIVE_PHASE_AND_GROUNDING_MEASUREMENT"
EXPECTED_CENTER_SAMPLE = 59
EXPECTED_CYCLE_SAMPLE_COUNT = 120


def assess(data: dict) -> dict:
    result = {"verdict": BLOCK, "runtime_authorized": False, "visual_approval_claimed": False}
    if not isinstance(data, dict):
        return result
    samples = data.get("samples")
    center = data.get("center_sample")
    radius = data.get("radius_samples")
    cycle = data.get("cycle_sample_count")
    baseline_center = data.get("baseline_source_plant_sample")
    baseline_cycle = data.get("baseline_cycle_sample_count")
    ints = (center, radius, cycle, baseline_center, baseline_cycle)
    if any(isinstance(v, bool) for v in ints):
        return result
    if not all(isinstance(v, int) for v in ints):
        return result
    if baseline_center != EXPECTED_CENTER_SAMPLE or baseline_cycle != EXPECTED_CYCLE_SAMPLE_COUNT:
        return result
    if center != baseline_center or cycle != baseline_cycle:
        return result
    if cycle <= 0 or radius <= 0 or radius >= cycle // 2 or not 0 <= center < cycle:
        return result
    if not isinstance(samples, list) or len(samples) != cycle:
        return result

    changed = []
    unchanged = 0
    active_abs_by_distance: dict[int, list[float]] = {}
    for i, sample in enumerate(samples):
        if not isinstance(sample, dict):
            return result
        angle = sample.get("rotation_delta_rad")
        length_error = sample.get("right_foot_length_error_m")
        left_delta = sample.get("left_foot_delta_m")
        values = (angle, length_error, left_delta)
        if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(float(v)) for v in values):
            return result
        if abs(float(length_error)) > 1e-6 or abs(float(left_delta)) > 1e-9:
            return result
        distance = min((i - center) % cycle, (center - i) % cycle)
        active = distance <= radius
        if active:
            active_abs_by_distance.setdefault(distance, []).append(abs(float(angle)))
            if abs(float(angle)) > 1e-9:
                changed.append(i)
        else:
            if abs(float(angle)) > 1e-9:
                return result
            unchanged += 1

    if len(changed) < 2 or unchanged == 0 or center not in changed:
        return result
    angles = [float(samples[i]["rotation_delta_rad"]) for i in changed]
    if max(angles) - min(angles) <= 1e-9:
        return result

    # Require a bounded taper: correction magnitude may stay flat but must not grow
    # as samples move away from the measured plant center.
    distance_levels = sorted(active_abs_by_distance)
    previous = None
    for distance in distance_levels:
        level = max(active_abs_by_distance[distance])
        if previous is not None and level > previous + 1e-9:
            return result
        previous = level

    result.update({
        "verdict": ALLOW,
        "changed_samples": changed,
        "bound_source_plant_sample": baseline_center,
        "bound_cycle_sample_count": baseline_cycle,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
    })
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    data = json.loads(args.evidence.read_text(encoding="utf-8"))
    print(json.dumps(assess(data), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
