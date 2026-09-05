#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ANALYZER_PATH = HERE / "analyze_civ1_fixed_length_reconstruction.py"
_spec = importlib.util.spec_from_file_location("civ1_fixed", ANALYZER_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("cannot load fixed-length analyzer")
fixed = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fixed)

CYCLE = 120
POSE_BONES = (
    "Hips",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
)


def _quat(v, label: str):
    if not isinstance(v, list) or len(v) != 4:
        raise ValueError(f"invalid {label}")
    q = [float(x) for x in v]
    if not all(math.isfinite(x) for x in q):
        raise ValueError(f"non-finite {label}")
    n = math.sqrt(sum(x * x for x in q))
    if n < 1e-12:
        raise ValueError(f"degenerate {label}")
    return [x / n for x in q]


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    q = [
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ]
    return _quat(q, "quaternion product")


def _bone_record(sample, semantic: str):
    try:
        record = sample["bones"][semantic]["target"]
    except (KeyError, TypeError) as exc:
        raise ValueError(f"missing target bone {semantic}") from exc
    origin = fixed.v3(record["model_origin"], f"{semantic}.origin")
    rotation = _quat(record["model_rotation_xyzw"], f"{semantic}.rotation")
    return origin, rotation


def _pose(origin, rotation):
    return {"origin": [float(x) for x in origin], "rotation_xyzw": _quat(rotation, "pose rotation")}


def _leg_pose(hip, knee_ref, foot_ref, goal, upper_q0, lower_q0, l1, l2):
    solved = fixed.solve_fixed(hip, knee_ref, foot_ref, goal, l1, l2)
    upper_delta = fixed.quat_from_to(fixed.sub(knee_ref, hip), fixed.sub(solved["knee"], hip))
    lower_delta = fixed.quat_from_to(fixed.sub(foot_ref, knee_ref), fixed.sub(goal, solved["knee"]))
    return solved, qmul(upper_delta, upper_q0), qmul(lower_delta, lower_q0)


def build(native, reconstruction):
    if reconstruction.get("schema") != "grand-bruxelles-civ1-fixed-length-reconstruction-v2":
        raise ValueError("unexpected reconstruction schema")
    if reconstruction.get("verdict") != "AMELIORER_FIXED_LENGTH_CONTINUOUS_CYCLE":
        raise ValueError("witness requires AMELIORER continuous cycle")
    if reconstruction.get("runtime_authorized") is not False or reconstruction.get("visual_approval_claimed") is not False:
        raise ValueError("witness input must remain non-production")
    if reconstruction.get("physical_envelope_pass") is not True or reconstruction.get("correction_continuity_pass") is not True:
        raise ValueError("witness requires physical + continuity pass")

    samples = native.get("model_space_samples")
    if not isinstance(samples, list) or len(samples) != CYCLE + 1:
        raise ValueError("expected 121 native samples")
    path = reconstruction.get("pelvis_path_mm")
    if not isinstance(path, list) or len(path) != CYCLE or any(isinstance(x, bool) or not isinstance(x, int) for x in path):
        raise ValueError("expected exact 120-sample integer pelvis path")
    shift = int(reconstruction["candidate"]["vertical_shift_samples"])
    if shift <= 0 or shift > fixed.MAX_SHIFT:
        raise ValueError("invalid selected shift")

    base_rel = [fixed.rel(samples[i], "RightFoot") for i in range(CYCLE)]
    frames = []
    worst_frame = 0
    worst_knee = -1.0
    max_origin_reconstruction_error = 0.0

    for i in range(CYCLE):
        sample = samples[i]
        if sample.get("sample_index") != i:
            raise ValueError("sample index drift")
        hips, hips_q = _bone_record(sample, "Hips")
        rh, rh_q = _bone_record(sample, "RightUpperLeg")
        rk, rk_q = _bone_record(sample, "RightLowerLeg")
        rf, rf_q = _bone_record(sample, "RightFoot")
        lh, lh_q = _bone_record(sample, "LeftUpperLeg")
        lk, lk_q = _bone_record(sample, "LeftLowerLeg")
        lf, lf_q = _bone_record(sample, "LeftFoot")

        dy = path[i] / 1000.0
        right_goal = [rf[0], hips[1] + base_rel[(i + shift) % CYCLE][1], rf[2]]
        left_goal = lf[:]
        right_hip = [rh[0], rh[1] + dy, rh[2]]
        left_hip = [lh[0], lh[1] + dy, lh[2]]
        rl1, rl2 = fixed.dist(rh, rk), fixed.dist(rk, rf)
        ll1, ll2 = fixed.dist(lh, lk), fixed.dist(lk, lf)

        right, right_upper_q, right_lower_q = _leg_pose(right_hip, rk, rf, right_goal, rh_q, rk_q, rl1, rl2)
        left, left_upper_q, left_lower_q = _leg_pose(left_hip, lk, lf, left_goal, lh_q, lk_q, ll1, ll2)

        right_knee_delta = fixed.dist(right["knee"], rk)
        left_knee_delta = fixed.dist(left["knee"], lk)
        frame_knee = max(right_knee_delta, left_knee_delta)
        if frame_knee > worst_knee:
            worst_knee = frame_knee
            worst_frame = i

        # The target origins below are an explicit global-pose witness contract.
        # Godot must reproduce them after set_bone_global_pose() before a screenshot is accepted.
        poses = {
            "Hips": _pose([hips[0], hips[1] + dy, hips[2]], hips_q),
            "RightUpperLeg": _pose(right_hip, right_upper_q),
            "RightLowerLeg": _pose(right["knee"], right_lower_q),
            "RightFoot": _pose(right_goal, rf_q),
            "LeftUpperLeg": _pose(left_hip, left_upper_q),
            "LeftLowerLeg": _pose(left["knee"], left_lower_q),
            "LeftFoot": _pose(left_goal, lf_q),
        }
        for semantic in POSE_BONES:
            if semantic not in poses:
                raise ValueError(f"missing pose {semantic}")
        max_origin_reconstruction_error = max(
            max_origin_reconstruction_error,
            right["upper_length_error_m"], right["lower_length_error_m"],
            left["upper_length_error_m"], left["lower_length_error_m"],
        )
        frames.append({
            "sample_index": i,
            "pelvis_delta_mm": path[i],
            "right_knee_correction_m": right_knee_delta,
            "left_knee_correction_m": left_knee_delta,
            "poses": poses,
        })

    if max_origin_reconstruction_error > 1e-7:
        raise ValueError("bundle reconstruction stretched a bone")

    return {
        "schema": "grand-bruxelles-civ1-skeleton-witness-bundle-v1",
        "diagnostic_only": True,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "source_reconstruction_verdict": reconstruction["verdict"],
        "frame_count": CYCLE,
        "selected_shift_samples": shift,
        "max_used_pelvis_mm": max(abs(x) for x in path),
        "max_knee_displacement_m": worst_knee,
        "max_bone_length_error_m": max_origin_reconstruction_error,
        "witness_frame": worst_frame,
        "frames": frames,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("native_json")
    ap.add_argument("reconstruction_json")
    ap.add_argument("output_json")
    args = ap.parse_args()
    native = json.loads(Path(args.native_json).read_text())
    reconstruction = json.loads(Path(args.reconstruction_json).read_text())
    result = build(native, reconstruction)
    Path(args.output_json).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(
        "CIV1_SKELETON_WITNESS_BUNDLE_OK "
        f"frames={result['frame_count']} witness_frame={result['witness_frame']} "
        f"pelvis_mm={result['max_used_pelvis_mm']} knee_m={result['max_knee_displacement_m']:.6f}"
    )


if __name__ == "__main__":
    main()
