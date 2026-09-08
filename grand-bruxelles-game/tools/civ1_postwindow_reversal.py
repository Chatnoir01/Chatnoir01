#!/usr/bin/env python3
import json
import math
import sys
from pathlib import Path

SKELETON_SCHEMA = "grand-bruxelles-civ1-skeleton-witness-bundle-v1"
PHASE_SCHEMA = "grand-bruxelles-civ1-contact-phase-causality-v1"
OUTPUT_SCHEMA = "grand-bruxelles-civ1-postwindow-reversal-v1"
PHASE_SAMPLES = [68, 69, 70, 71]


def load(path: str) -> dict:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"not-an-object:{path}")
    return data


def y_series(frames, bone: str):
    out = []
    for i, frame in enumerate(frames):
        origin = frame.get("poses", {}).get(bone, {}).get("origin", [])
        if len(origin) != 3:
            raise ValueError(f"pose-shape:{bone}:{i}")
        y = float(origin[1])
        if not math.isfinite(y):
            raise ValueError(f"nonfinite:{bone}:{i}")
        out.append(y)
    return out


def reversal_candidates(values):
    # Exact sign reversal only: descending into frame i, non-descending out of i.
    return [i for i in range(1, len(values) - 1)
            if values[i] - values[i - 1] < 0.0 and values[i + 1] - values[i] >= 0.0]


def first_after(candidates, index):
    return next((i for i in candidates if i > index), None)


def main() -> int:
    if len(sys.argv) != 4:
        print("CIV1_POSTWINDOW_REVERSAL_FAIL:args", file=sys.stderr)
        return 2
    skeleton = load(sys.argv[1])
    phase = load(sys.argv[2])
    if skeleton.get("schema") != SKELETON_SCHEMA:
        print("CIV1_POSTWINDOW_REVERSAL_FAIL:skeleton-schema", file=sys.stderr)
        return 3
    if phase.get("schema") != PHASE_SCHEMA or phase.get("sample_indices") != PHASE_SAMPLES:
        print("CIV1_POSTWINDOW_REVERSAL_FAIL:phase-schema", file=sys.stderr)
        return 4
    if phase.get("strict_rightfoot_descent") is not True or phase.get("strict_lower_envelope_descent") is not True:
        print("CIV1_POSTWINDOW_REVERSAL_FAIL:phase-not-descending", file=sys.stderr)
        return 5
    frames = skeleton.get("frames", [])
    if len(frames) != 120:
        print("CIV1_POSTWINDOW_REVERSAL_FAIL:frame-count", file=sys.stderr)
        return 6

    hips = y_series(frames, "Hips")
    foot = y_series(frames, "RightFoot")
    toe = y_series(frames, "RightToeBase")
    foot_candidates = reversal_candidates(foot)
    toe_candidates = reversal_candidates(toe)
    foot_next = first_after(foot_candidates, PHASE_SAMPLES[-1])
    toe_next = first_after(toe_candidates, PHASE_SAMPLES[-1])
    common = sorted(set(foot_candidates).intersection(toe_candidates))
    common_next = first_after(common, PHASE_SAMPLES[-1])

    report = {
        "schema": OUTPUT_SCHEMA,
        "diagnostic_only": True,
        "source_phase_samples": PHASE_SAMPLES,
        "frame_count": 120,
        "rightfoot_reversal_candidates": foot_candidates,
        "righttoebase_reversal_candidates": toe_candidates,
        "common_reversal_candidates": common,
        "first_rightfoot_reversal_after_window": foot_next,
        "first_righttoebase_reversal_after_window": toe_next,
        "first_common_reversal_after_window": common_next,
        "hips_y_span_m": max(hips) - min(hips),
        "candidate_is_ground_contact_proof": False,
        "planted_interval_claimable": False,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "next_evidence_window": ([common_next - 1, common_next, common_next + 1]
                                 if common_next is not None else []),
    }
    Path(sys.argv[3]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CIV1_POSTWINDOW_REVERSAL_OK",
          f"foot={foot_next}", f"toe={toe_next}", f"common={common_next}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
