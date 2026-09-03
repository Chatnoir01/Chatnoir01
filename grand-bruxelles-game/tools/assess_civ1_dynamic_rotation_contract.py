#!/usr/bin/env python3
"""Fail-closed contract for CIV-1 time-varying RightFoot rotation candidates.

This gate does not authorize runtime or visual approval. It only checks that a
candidate is genuinely time-varying/localized and preserves hard structural rails
before native Godot grounding measurements are considered.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

BLOCK = "BLOCK_DYNAMIC_ROTATION_CONTRACT"
ALLOW = "REQUIRE_NATIVE_PHASE_AND_GROUNDING_MEASUREMENT"


def assess(data: dict) -> dict:
    result = {"verdict": BLOCK, "runtime_authorized": False, "visual_approval_claimed": False}
    if not isinstance(data, dict):
        return result
    samples = data.get("samples")
    center = data.get("center_sample")
    radius = data.get("radius_samples")
    cycle = data.get("cycle_sample_count")
    if isinstance(center, bool) or isinstance(radius, bool) or isinstance(cycle, bool):
        return result
    if not all(isinstance(v, int) for v in (center, radius, cycle)):
        return result
    if cycle <= 0 or radius <= 0 or radius >= cycle // 2 or not 0 <= center < cycle:
        return result
    if not isinstance(samples, list) or len(samples) != cycle:
        return result

    changed = []
    unchanged = 0
    for i, sample in enumerate(samples):
        if not isinstance(sample, dict):
            return result
        angle = sample.get("rotation_delta_rad")
        length_error = sample.get("right_foot_length_error_m")
        left_delta = sample.get("left_foot_delta_m")
        if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(float(v)) for v in (angle, length_error, left_delta)):
            return result
        if abs(float(length_error)) > 1e-6 or abs(float(left_delta)) > 1e-9:
            return result
        distance = min((i - center) % cycle, (center - i) % cycle)
        active = distance <= radius
        if active:
            if abs(float(angle)) > 1e-9:
                changed.append(i)
        else:
            if abs(float(angle)) > 1e-9:
                return result
            unchanged += 1

    if len(changed) < 2 or unchanged == 0:
        return result
    angles = [float(samples[i]["rotation_delta_rad"]) for i in changed]
    if max(angles) - min(angles) <= 1e-9:
        return result

    result.update({
        "verdict": ALLOW,
        "changed_samples": changed,
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
