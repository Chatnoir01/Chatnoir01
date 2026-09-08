#!/usr/bin/env python3
import json
import math
import sys
from pathlib import Path

TARGET_SAMPLES = [68, 69, 70, 71]
GEOMETRY_SCHEMA = "grand-bruxelles-civ1-geometry-derived-placement-v1"
SKELETON_SCHEMA = "grand-bruxelles-civ1-skeleton-witness-bundle-v1"
OUTPUT_SCHEMA = "grand-bruxelles-civ1-contact-phase-causality-v1"


def _load(path: str) -> dict:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"not-an-object:{path}")
    return data


def _finite(values) -> bool:
    return all(math.isfinite(float(v)) for v in values)


def main() -> int:
    if len(sys.argv) != 4:
        print("CIV1_CONTACT_PHASE_FAIL:args", file=sys.stderr)
        return 2
    geometry = _load(sys.argv[1])
    skeleton = _load(sys.argv[2])
    if geometry.get("schema") != GEOMETRY_SCHEMA:
        print("CIV1_CONTACT_PHASE_FAIL:geometry-schema", file=sys.stderr)
        return 3
    if skeleton.get("schema") != SKELETON_SCHEMA:
        print("CIV1_CONTACT_PHASE_FAIL:skeleton-schema", file=sys.stderr)
        return 4
    if geometry.get("sample_indices") != TARGET_SAMPLES or int(geometry.get("fixed_vertex_count", -1)) != 3306:
        print("CIV1_CONTACT_PHASE_FAIL:geometry-shape", file=sys.stderr)
        return 5
    samples = geometry.get("samples", [])
    frames = skeleton.get("frames", [])
    if len(samples) != 4 or len(frames) != 120:
        print("CIV1_CONTACT_PHASE_FAIL:evidence-shape", file=sys.stderr)
        return 6

    by_sample = {int(row.get("sample_index", -1)): row for row in samples}
    hips_y = []
    rightfoot_y = []
    raw_lower_y = []
    geometry_placement_y = []
    for index in TARGET_SAMPLES:
        if index not in by_sample:
            print("CIV1_CONTACT_PHASE_FAIL:sample-join", file=sys.stderr)
            return 7
        poses = frames[index].get("poses", {})
        hips = poses.get("Hips", {}).get("origin", [])
        foot = poses.get("RightFoot", {}).get("origin", [])
        if len(hips) != 3 or len(foot) != 3:
            print("CIV1_CONTACT_PHASE_FAIL:pose-shape", file=sys.stderr)
            return 8
        hips_y.append(float(hips[1]))
        rightfoot_y.append(float(foot[1]))
        raw_lower_y.append(float(by_sample[index]["raw_lower_envelope_y_m"]))
        geometry_placement_y.append(float(by_sample[index]["geometry_derived_placement_y_m"]))

    if not _finite(hips_y + rightfoot_y + raw_lower_y + geometry_placement_y):
        print("CIV1_CONTACT_PHASE_FAIL:nonfinite", file=sys.stderr)
        return 9

    raw_steps = [raw_lower_y[i + 1] - raw_lower_y[i] for i in range(3)]
    foot_steps = [rightfoot_y[i + 1] - rightfoot_y[i] for i in range(3)]
    placement_steps = [geometry_placement_y[i + 1] - geometry_placement_y[i] for i in range(3)]
    hips_span = max(hips_y) - min(hips_y)
    raw_span = max(raw_lower_y) - min(raw_lower_y)
    foot_span = max(rightfoot_y) - min(rightfoot_y)
    strict_envelope_descent = all(step < 0.0 for step in raw_steps)
    strict_rightfoot_descent = all(step < 0.0 for step in foot_steps)
    source_hips_static = hips_span == 0.0
    planted_interval_claimable = False

    report = {
        "schema": OUTPUT_SCHEMA,
        "diagnostic_only": True,
        "sample_indices": TARGET_SAMPLES,
        "fixed_vertex_count": 3306,
        "hips_y_m": hips_y,
        "rightfoot_y_m": rightfoot_y,
        "raw_lower_envelope_y_m": raw_lower_y,
        "geometry_derived_placement_y_m": geometry_placement_y,
        "raw_lower_envelope_step_m": raw_steps,
        "rightfoot_step_m": foot_steps,
        "geometry_placement_step_m": placement_steps,
        "hips_y_span_m": hips_span,
        "rightfoot_y_span_m": foot_span,
        "raw_lower_envelope_span_m": raw_span,
        "source_hips_static": source_hips_static,
        "strict_rightfoot_descent": strict_rightfoot_descent,
        "strict_lower_envelope_descent": strict_envelope_descent,
        "root_motion_explains_descent": not source_hips_static,
        "contact_plateau_observed": False,
        "planted_interval_claimable": planted_interval_claimable,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
    }
    Path(sys.argv[3]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "CIV1_CONTACT_PHASE_OK",
        f"hips_span={hips_span:.9f}",
        f"foot_span={foot_span:.9f}",
        f"envelope_span={raw_span:.9f}",
        f"strict_descent={strict_envelope_descent}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
