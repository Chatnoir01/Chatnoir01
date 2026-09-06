#!/usr/bin/env python3
"""Build an independent RightFoot diagnostic harness from the validated LeftFoot one.

The validated witness is intentionally bilateral: pose application, bone aliases and
bilateral floor placement must retain both feet. Only the diagnostic target side is
rewritten. Frozen camera/raster/Skeleton rails remain unchanged. QA only; no runtime.
"""
from __future__ import annotations
import sys
from pathlib import Path

GENERIC_REPLACEMENTS = (
    ("LEFTFOOT", "RIGHTFOOT"),
    ("LeftFoot", "RightFoot"),
    ("leftfoot", "rightfoot"),
    ("DiagnosticLeftFootLandmark", "DiagnosticRightFootLandmark"),
)

# These validated upstream structures are intentionally bilateral and MUST survive
# byte-for-byte. Protecting them prevents the prior RED where naive global token
# substitution produced duplicate RightFoot dictionary keys in ALIASES.
POSE_BONES_LINE = 'const POSE_BONES := ["Hips", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]'
ALIASES_BLOCK = '''const ALIASES := {
    "Hips":["hips","pelvis"], "RightUpperLeg":["rightupperleg","rightupleg","rupperleg"],
    "RightLowerLeg":["rightlowerleg","rightleg","rlowerleg"], "RightFoot":["rightfoot","rfoot"],
    "LeftUpperLeg":["leftupperleg","leftupleg","lupperleg"], "LeftLowerLeg":["leftlowerleg","leftleg","llowerleg"],
    "LeftFoot":["leftfoot","lfoot"]
}'''
BILATERAL_FLOOR_LINE = '        bilateral_floor_y=min(bilateral_floor_y,_frame_pose(frame,"LeftFoot").origin.y,_frame_pose(frame,"RightFoot").origin.y)'


def _replace_semantic_target(text: str) -> str:
    out = text
    for old, new in GENERIC_REPLACEMENTS:
        out = out.replace(old, new)
    return out


def _transform_witness(before: str) -> str:
    protected = (
        (POSE_BONES_LINE, "__CIV1_PROTECTED_POSE_BONES__"),
        (ALIASES_BLOCK, "__CIV1_PROTECTED_ALIASES__"),
        (BILATERAL_FLOOR_LINE, "__CIV1_PROTECTED_BILATERAL_FLOOR__"),
    )
    out = before
    for snippet, marker in protected:
        if out.count(snippet) != 1:
            raise ValueError(f"witness: validated bilateral structure missing/drifted: {marker}")
        out = out.replace(snippet, marker, 1)
    out = _replace_semantic_target(out)
    for snippet, marker in protected:
        if out.count(marker) != 1:
            raise ValueError(f"witness: protected marker corrupted: {marker}")
        out = out.replace(marker, snippet, 1)

    # Causal regression guard for the observed RED: exactly one alias entry per foot.
    if out.count('"RightFoot":["rightfoot","rfoot"]') != 1:
        raise ValueError("witness: RightFoot alias cardinality changed")
    if out.count('"LeftFoot":["leftfoot","lfoot"]') != 1:
        raise ValueError("witness: LeftFoot alias cardinality changed")
    if 'mapping["RightFoot"]' not in out or 'rightfoot_bone_name' not in out:
        raise ValueError("witness: diagnostic target did not move to RightFoot")
    if 'mapping["LeftFoot"]' in out.replace(BILATERAL_FLOOR_LINE, ""):
        raise ValueError("witness: residual diagnostic LeftFoot mapping outside bilateral floor")
    return out


def transform(text: str, kind: str) -> str:
    before = text
    required = {
        "witness": (
            "LeftFoot", "RightFoot", "leftfoot_bone_pose_with_verified_same_skeleton_skin",
            "MARKER_RADIUS_M := 0.025", "marker_mat.no_depth_test=true", POSE_BONES_LINE,
            ALIASES_BLOCK, BILATERAL_FLOOR_LINE,
        ),
        "analyzer": (
            "LeftFoot", "MAX_CENTROID_ERROR_PX=1.5", "MAX_PATH_REL_ERROR=0.25",
            "magenta_raster_of_verified_leftfoot_bone_pose",
        ),
    }[kind]
    for token in required:
        if token not in before:
            raise ValueError(f"{kind}: validated upstream token missing: {token}")

    out = _transform_witness(before) if kind == "witness" else _replace_semantic_target(before)
    if out == before:
        raise ValueError(f"{kind}: no semantic transformation applied")

    frozen = (
        "1280", "720", "45.0", "[2.0, 4.0, 8.0]", "[114, 115, 116, 117, 118]"
    ) if kind == "witness" else (
        "DISTANCES=(2,4,8)", "SAMPLES=(114,115,116,117,118)",
        "MAX_CENTROID_ERROR_PX=1.5", "MAX_PATH_REL_ERROR=0.25",
    )
    for token in frozen:
        if token not in out:
            raise ValueError(f"{kind}: frozen rail changed or missing: {token}")

    if kind == "analyzer":
        residual = [token for token in ("LeftFoot", "leftfoot", "LEFTFOOT") if token in out]
        if residual:
            raise ValueError(f"analyzer: residual left-foot diagnostic tokens: {residual}")
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print("usage: build_civ1_rightfoot_landmark_from_validated_left.py LEFT_WITNESS.gd LEFT_ANALYZER.py OUT_WITNESS.gd OUT_ANALYZER.py", file=sys.stderr)
        return 2
    left_witness, left_analyzer, out_witness, out_analyzer = map(Path, argv[1:])
    try:
        witness = transform(left_witness.read_text(encoding="utf-8"), "witness")
        analyzer = transform(left_analyzer.read_text(encoding="utf-8"), "analyzer")
        out_witness.write_text(witness, encoding="utf-8")
        out_analyzer.write_text(analyzer, encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_RIGHTFOOT_HARNESS_BUILD_FAIL: {exc}", file=sys.stderr)
        return 3
    print("CIV1_RIGHTFOOT_HARNESS_BUILD_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
