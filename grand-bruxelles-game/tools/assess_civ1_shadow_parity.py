#!/usr/bin/env python3
"""Fail-closed semantic parity assessor for historical vs shadow CIV-1 diagnostics.

Two independent Godot runs are not required to serialize every sampled float bit-identically.
This gate instead requires the diagnostic contract and all promotion-relevant conclusions to
match, while allowing at most one sample of non-material phase jitter.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

PHASE_TOLERANCE_SAMPLES = 1
EXACT_TOP_LEVEL = (
    "format",
    "source_animation",
    "sample_count",
    "retarget_modifier",
    "use_global_pose",
    "position_enabled",
    "rotation_enabled",
    "scale_enabled",
    "diagnostic_bones",
    "first_material_divergence_joint",
    "diagnostic_only",
    "runtime_authorized",
    "visual_approval_claimed",
    "right_foot_reference_ab",
)


def assess(base: dict, shadow: dict) -> dict:
    failures: list[str] = []
    for key in EXACT_TOP_LEVEL:
        if base.get(key) != shadow.get(key):
            failures.append(f"top_level_mismatch:{key}")

    base_phase = base.get("phase_vertical_summary", {})
    shadow_phase = shadow.get("phase_vertical_summary", {})
    if base_phase.get("material_threshold_samples") != shadow_phase.get("material_threshold_samples"):
        failures.append("phase_threshold_mismatch")
    if base_phase.get("first_material_divergence_joint") != shadow_phase.get("first_material_divergence_joint"):
        failures.append("first_material_joint_mismatch")

    base_bones = base_phase.get("per_bone", {})
    shadow_bones = shadow_phase.get("per_bone", {})
    if set(base_bones) != set(shadow_bones):
        failures.append("phase_bone_inventory_mismatch")
    else:
        for bone in sorted(base_bones):
            a = base_bones[bone]
            b = shadow_bones[bone]
            if a.get("material_phase_divergence") != b.get("material_phase_divergence"):
                failures.append(f"material_class_mismatch:{bone}")
            for field in (
                "source_vertical_min_sample_index",
                "target_vertical_min_sample_index",
                "phase_delta_samples",
            ):
                try:
                    delta = abs(int(a[field]) - int(b[field]))
                except (KeyError, TypeError, ValueError):
                    failures.append(f"missing_phase_field:{bone}:{field}")
                    continue
                if delta > PHASE_TOLERANCE_SAMPLES:
                    failures.append(f"phase_jitter_exceeded:{bone}:{field}:{delta}")

    return {
        "format": "grand-bruxelles-civ1-shadow-parity-v1",
        "semantic_parity_verified": not failures,
        "phase_tolerance_samples": PHASE_TOLERANCE_SAMPLES,
        "failures": failures,
        "verdict": "ALLOW_QA_SHADOW_PARITY" if not failures else "BLOCK_SHADOW_PARITY",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("historical", type=Path)
    parser.add_argument("shadow", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    base = json.loads(args.historical.read_text(encoding="utf-8"))
    shadow = json.loads(args.shadow.read_text(encoding="utf-8"))
    result = assess(base, shadow)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(result["verdict"])
    return 0 if result["semantic_parity_verified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
