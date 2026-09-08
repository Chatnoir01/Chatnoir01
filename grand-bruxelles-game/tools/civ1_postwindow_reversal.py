#!/usr/bin/env python3
import json
import math
import sys
from pathlib import Path

SKELETON_SCHEMA = "grand-bruxelles-civ1-skeleton-witness-bundle-v1"
PHASE_SCHEMA = "grand-bruxelles-civ1-contact-phase-causality-v1"
TOE_SCHEMA = "grand-bruxelles-civ1-righttoebase-pose-v1"
OUTPUT_SCHEMA = "grand-bruxelles-civ1-postwindow-reversal-v2"
PHASE_SAMPLES = [68, 69, 70, 71]
ANCHOR_TOLERANCE_M = 1e-6
LOCAL_ORIGIN_TOLERANCE_M = 1e-6
LOCAL_QUAT_TOLERANCE = 1e-6


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


def vec3(values):
    if not isinstance(values, list) or len(values) != 3:
        raise ValueError("vec3-shape")
    out = tuple(float(v) for v in values)
    if not all(math.isfinite(v) for v in out):
        raise ValueError("vec3-nonfinite")
    return out


def quat(values):
    if not isinstance(values, list) or len(values) != 4:
        raise ValueError("quat-shape")
    out = tuple(float(v) for v in values)
    if not all(math.isfinite(v) for v in out):
        raise ValueError("quat-nonfinite")
    norm = math.sqrt(sum(v * v for v in out))
    if norm <= 0.0:
        raise ValueError("quat-zero")
    return tuple(v / norm for v in out)


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def qconj(q):
    return (-q[0], -q[1], -q[2], q[3])


def qrotate(q, v):
    r = qmul(qmul(q, (v[0], v[1], v[2], 0.0)), qconj(q))
    return (r[0], r[1], r[2])


def transform_compose(parent_origin, parent_rotation, local_origin, local_rotation):
    rotated = qrotate(parent_rotation, local_origin)
    origin = tuple(parent_origin[i] + rotated[i] for i in range(3))
    rotation = quat(list(qmul(parent_rotation, local_rotation)))
    return origin, rotation


def distance(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


def quat_delta(a, b):
    return min(
        math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(4))),
        math.sqrt(sum((a[i] + b[i]) ** 2 for i in range(4))),
    )


def toe_relative_transform(toe_pose):
    if toe_pose.get("schema") != TOE_SCHEMA:
        raise ValueError("toe-schema")
    if toe_pose.get("sample_indices") != PHASE_SAMPLES:
        raise ValueError("toe-samples")
    samples = toe_pose.get("samples", [])
    if len(samples) != len(PHASE_SAMPLES):
        raise ValueError("toe-sample-count")
    first = samples[0].get("source_righttoebase_relative_to_rightfoot", {})
    local_origin = vec3(first.get("origin", []))
    local_rotation = quat(first.get("rotation_xyzw", []))
    for sample in samples[1:]:
        rec = sample.get("source_righttoebase_relative_to_rightfoot", {})
        origin = vec3(rec.get("origin", []))
        rotation = quat(rec.get("rotation_xyzw", []))
        if distance(origin, local_origin) > LOCAL_ORIGIN_TOLERANCE_M:
            raise ValueError("toe-local-origin-not-static")
        if quat_delta(rotation, local_rotation) > LOCAL_QUAT_TOLERANCE:
            raise ValueError("toe-local-rotation-not-static")
    return local_origin, local_rotation


def reconstruct_toe_series(frames, toe_local):
    local_origin, local_rotation = toe_local
    origins = []
    for i, frame in enumerate(frames):
        foot = frame.get("poses", {}).get("RightFoot", {})
        foot_origin = vec3(foot.get("origin", []))
        foot_rotation = quat(foot.get("rotation_xyzw", []))
        origin, _ = transform_compose(foot_origin, foot_rotation, local_origin, local_rotation)
        if not all(math.isfinite(v) for v in origin):
            raise ValueError(f"toe-reconstruct-nonfinite:{i}")
        origins.append(origin)
    return origins


def validate_toe_anchor_samples(frames, toe_pose, toe_local):
    reconstructed = reconstruct_toe_series(frames, toe_local)
    max_error = 0.0
    for sample in toe_pose.get("samples", []):
        index = int(sample.get("sample_index", -1))
        if index not in PHASE_SAMPLES:
            raise ValueError("toe-anchor-index")
        expected = vec3(sample.get("derived_righttoebase_global", {}).get("origin", []))
        error = distance(reconstructed[index], expected)
        max_error = max(max_error, error)
    if max_error > ANCHOR_TOLERANCE_M:
        raise ValueError(f"toe-anchor-drift:{max_error}")
    return max_error


def reversal_candidates(values):
    return [i for i in range(1, len(values) - 1)
            if values[i] - values[i - 1] < 0.0 and values[i + 1] - values[i] >= 0.0]


def first_after(candidates, index):
    return next((i for i in candidates if i > index), None)


def main() -> int:
    if len(sys.argv) != 5:
        print("CIV1_POSTWINDOW_REVERSAL_FAIL:args", file=sys.stderr)
        return 2
    skeleton = load(sys.argv[1])
    phase = load(sys.argv[2])
    toe_pose = load(sys.argv[3])
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
    toe_local = toe_relative_transform(toe_pose)
    toe_origins = reconstruct_toe_series(frames, toe_local)
    toe_anchor_error = validate_toe_anchor_samples(frames, toe_pose, toe_local)
    toe = [origin[1] for origin in toe_origins]

    foot_candidates = reversal_candidates(foot)
    foot_next = first_after(foot_candidates, PHASE_SAMPLES[-1])
    toe_candidates = reversal_candidates(toe)
    toe_next = first_after(toe_candidates, PHASE_SAMPLES[-1])
    common = sorted(set(foot_candidates).intersection(toe_candidates))
    common_next = first_after(common, PHASE_SAMPLES[-1])

    report = {
        "schema": OUTPUT_SCHEMA,
        "diagnostic_only": True,
        "source_phase_samples": PHASE_SAMPLES,
        "frame_count": 120,
        "rightfoot_reversal_candidates": foot_candidates,
        "righttoebase_series_available": True,
        "righttoebase_series_coverage_count": len(toe),
        "righttoebase_series_first_missing_frame": None,
        "righttoebase_reconstruction_basis": "validated_rightfoot_global_x_static_source_toebase_relative_transform",
        "righttoebase_anchor_max_origin_error_m": toe_anchor_error,
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
        "toe_coverage_required_before_common_candidate": False,
        "next_evidence_window": ([common_next - 1, common_next, common_next + 1]
                                 if common_next is not None else []),
    }
    Path(sys.argv[4]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CIV1_POSTWINDOW_REVERSAL_OK",
          f"foot={foot_next}", f"toe={toe_next}", f"common={common_next}",
          f"toe_coverage={len(toe)}", f"anchor_error={toe_anchor_error:.9g}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
