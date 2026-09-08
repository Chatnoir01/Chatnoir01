#!/usr/bin/env python3
import json
import math
import sys
from pathlib import Path

SKELETON_SCHEMA = "grand-bruxelles-civ1-skeleton-witness-bundle-v1"
TOE_SCHEMA = "grand-bruxelles-civ1-righttoebase-pose-v1"
OUTPUT_SCHEMA = "grand-bruxelles-civ1-ground-candidate-windows-v1"
PHASE_SAMPLES = [68, 69, 70, 71]
ANCHOR_TOLERANCE_M = 1e-6
LOCAL_TOLERANCE = 1e-6


def load(path: str) -> dict:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"not-an-object:{path}")
    return data


def vec(values, size: int, label: str):
    if not isinstance(values, list) or len(values) != size:
        raise ValueError(f"shape:{label}")
    out = tuple(float(v) for v in values)
    if not all(math.isfinite(v) for v in out):
        raise ValueError(f"nonfinite:{label}")
    return out


def quat(values, label: str):
    q = vec(values, 4, label)
    norm = math.sqrt(sum(v * v for v in q))
    if norm <= 0.0:
        raise ValueError(f"zero-quat:{label}")
    return tuple(v / norm for v in q)


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


def distance(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(len(a))))


def quat_delta(a, b):
    return min(distance(a, b), distance(a, tuple(-v for v in b)))


def y_series(frames, bone: str):
    values = []
    for i, frame in enumerate(frames):
        origin = vec(frame.get("poses", {}).get(bone, {}).get("origin", []), 3, f"{bone}:{i}:origin")
        values.append(origin[1])
    return values


def stable_toe_local_origin(toe_pose):
    if toe_pose.get("schema") != TOE_SCHEMA:
        raise ValueError("toe-schema")
    if toe_pose.get("sample_indices") != PHASE_SAMPLES:
        raise ValueError("toe-samples")
    samples = toe_pose.get("samples", [])
    if len(samples) != len(PHASE_SAMPLES):
        raise ValueError("toe-sample-count")
    first = samples[0]["source_righttoebase_relative_to_rightfoot"]
    origin0 = vec(first.get("origin", []), 3, "toe-local-origin:0")
    rotation0 = quat(first.get("rotation_xyzw", []), "toe-local-rotation:0")
    max_origin_drift = 0.0
    max_rotation_delta = 0.0
    for i, sample in enumerate(samples[1:], 1):
        rec = sample["source_righttoebase_relative_to_rightfoot"]
        origin = vec(rec.get("origin", []), 3, f"toe-local-origin:{i}")
        rotation = quat(rec.get("rotation_xyzw", []), f"toe-local-rotation:{i}")
        max_origin_drift = max(max_origin_drift, distance(origin, origin0))
        max_rotation_delta = max(max_rotation_delta, quat_delta(rotation, rotation0))
    if max_origin_drift > LOCAL_TOLERANCE:
        raise ValueError(f"toe-local-origin-drift:{max_origin_drift}")
    # Only the child origin is needed to reconstruct RightToeBase global origin.
    # Child-local rotation is validated as finite above and recorded diagnostically,
    # but it cannot move the child origin and therefore must not gate this position witness.
    return origin0, max_origin_drift, max_rotation_delta


def reconstruct_toe(frames, local_origin):
    result = []
    for i, frame in enumerate(frames):
        foot = frame.get("poses", {}).get("RightFoot", {})
        foot_origin = vec(foot.get("origin", []), 3, f"RightFoot:{i}:origin")
        foot_rotation = quat(foot.get("rotation_xyzw", []), f"RightFoot:{i}:rotation")
        rotated = qrotate(foot_rotation, local_origin)
        result.append(tuple(foot_origin[j] + rotated[j] for j in range(3)))
    return result


def validate_anchors(toe_origins, toe_pose):
    max_error = 0.0
    for sample in toe_pose["samples"]:
        index = int(sample["sample_index"])
        expected = vec(sample["derived_righttoebase_global"]["origin"], 3, f"anchor:{index}")
        max_error = max(max_error, distance(toe_origins[index], expected))
    if max_error > ANCHOR_TOLERANCE_M:
        raise ValueError(f"toe-anchor-drift:{max_error}")
    return max_error


def reversals(values):
    return [
        i for i in range(1, len(values) - 1)
        if values[i] - values[i - 1] < 0.0 and values[i + 1] - values[i] >= 0.0
    ]


def evidence_windows(foot_candidates, toe_candidates, frame_count):
    events = []
    for bone, candidates in (("RightFoot", foot_candidates), ("RightToeBase", toe_candidates)):
        for center in candidates:
            if center <= 0 or center >= frame_count - 1:
                continue
            events.append({"bone": bone, "center": center, "samples": [center - 1, center, center + 1]})
    events.sort(key=lambda item: (item["center"], item["bone"]))
    unique_sample_windows = sorted({tuple(item["samples"]) for item in events})
    return events, [list(window) for window in unique_sample_windows]


def main() -> int:
    if len(sys.argv) != 4:
        print("CIV1_GROUND_WINDOWS_FAIL:args", file=sys.stderr)
        return 2
    skeleton = load(sys.argv[1])
    toe_pose = load(sys.argv[2])
    if skeleton.get("schema") != SKELETON_SCHEMA:
        print("CIV1_GROUND_WINDOWS_FAIL:skeleton-schema", file=sys.stderr)
        return 3
    frames = skeleton.get("frames", [])
    if len(frames) != 120:
        print("CIV1_GROUND_WINDOWS_FAIL:frame-count", file=sys.stderr)
        return 4

    foot_y = y_series(frames, "RightFoot")
    toe_local_origin, toe_origin_drift, toe_rotation_delta = stable_toe_local_origin(toe_pose)
    toe_origins = reconstruct_toe(frames, toe_local_origin)
    anchor_error = validate_anchors(toe_origins, toe_pose)
    toe_y = [origin[1] for origin in toe_origins]
    foot_candidates = reversals(foot_y)
    toe_candidates = reversals(toe_y)
    events, windows = evidence_windows(foot_candidates, toe_candidates, len(frames))

    report = {
        "schema": OUTPUT_SCHEMA,
        "diagnostic_only": True,
        "frame_count": len(frames),
        "prior_descending_phase_samples": PHASE_SAMPLES,
        "rightfoot_reversal_candidates": foot_candidates,
        "righttoebase_reversal_candidates": toe_candidates,
        "exact_common_reversal_candidates": sorted(set(foot_candidates).intersection(toe_candidates)),
        "righttoebase_local_origin_max_drift_m": toe_origin_drift,
        "righttoebase_local_rotation_max_quaternion_delta": toe_rotation_delta,
        "righttoebase_local_rotation_diagnostic_only": True,
        "righttoebase_anchor_max_origin_error_m": anchor_error,
        "candidate_events": events,
        "same_sample_ground_geometry_windows": windows,
        "window_count": len(windows),
        "window_semantics": "kinematic-reversal-neighborhood-only",
        "requires_canonical_ground_same_sample": True,
        "requires_skinned_geometry_same_sample": True,
        "candidate_is_ground_contact_proof": False,
        "planted_interval_claimable": False,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
    }
    Path(sys.argv[3]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "CIV1_GROUND_WINDOWS_OK",
        f"events={len(events)}",
        f"windows={len(windows)}",
        f"anchor_error={anchor_error:.9g}",
        f"local_origin_drift={toe_origin_drift:.9g}",
        f"local_rotation_delta={toe_rotation_delta:.9g}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
