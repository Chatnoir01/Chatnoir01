#!/usr/bin/env python3
"""Build and verify an independent RightFoot diagnostic harness from validated LeftFoot evidence.

The validated witness is intentionally bilateral: pose application, bone aliases and
bilateral floor placement retain both feet byte-for-byte. Only the diagnostic target
side is rewritten. QA only; no runtime mutation.
"""
from __future__ import annotations
import sys
from pathlib import Path

GENERIC_REPLACEMENTS = (
    ("LEFTFOOT", "RIGHTFOOT"),
    ("LeftFoot", "RightFoot"),
    ("leftfoot", "rightfoot"),
)
POSE_BONES_LINE = 'const POSE_BONES := ["Hips", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]'
ALIASES_BLOCK = '''const ALIASES := {
    "Hips":["hips","pelvis"], "RightUpperLeg":["rightupperleg","rightupleg","rupperleg"],
    "RightLowerLeg":["rightlowerleg","rightleg","rlowerleg"], "RightFoot":["rightfoot","rfoot"],
    "LeftUpperLeg":["leftupperleg","leftupleg","lupperleg"], "LeftLowerLeg":["leftlowerleg","leftleg","llowerleg"],
    "LeftFoot":["leftfoot","lfoot"]
}'''
BILATERAL_FLOOR_LINE = '        bilateral_floor_y=min(bilateral_floor_y,_frame_pose(frame,"LeftFoot").origin.y,_frame_pose(frame,"RightFoot").origin.y)'
RIGHT_ALIAS = '"RightFoot":["rightfoot","rfoot"]'
LEFT_ALIAS = '"LeftFoot":["leftfoot","lfoot"]'

WITNESS_FROZEN = (
    "1280", "720", "45.0", "[2.0, 4.0, 8.0]", "[114, 115, 116, 117, 118]",
    "MARKER_RADIUS_M := 0.025", "marker_mat.no_depth_test=true",
)
ANALYZER_FROZEN = (
    "DISTANCES=(2,4,8)", "SAMPLES=(114,115,116,117,118)",
    "MAX_CENTROID_ERROR_PX=1.5", "MAX_PATH_REL_ERROR=0.25",
)


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
    return out


def validate_outputs(witness: str, analyzer: str) -> None:
    for token in WITNESS_FROZEN:
        if token not in witness:
            raise ValueError(f"witness: frozen rail changed or missing: {token}")
    for token in ANALYZER_FROZEN:
        if token not in analyzer:
            raise ValueError(f"analyzer: frozen rail changed or missing: {token}")
    for token in (POSE_BONES_LINE, ALIASES_BLOCK, BILATERAL_FLOOR_LINE):
        if witness.count(token) != 1:
            raise ValueError("witness: protected bilateral structure cardinality changed")
    if witness.count(RIGHT_ALIAS) != 1 or witness.count(LEFT_ALIAS) != 1:
        raise ValueError("witness: foot alias cardinality changed")
    if 'mapping["RightFoot"]' not in witness or 'rightfoot_bone_name' not in witness:
        raise ValueError("witness: diagnostic target did not move to RightFoot")
    diagnostic_without_floor = witness.replace(BILATERAL_FLOOR_LINE, "")
    if 'mapping["LeftFoot"]' in diagnostic_without_floor:
        raise ValueError("witness: residual diagnostic LeftFoot mapping outside bilateral floor")
    for token in ("LeftFoot", "leftfoot", "LEFTFOOT"):
        if token in analyzer:
            raise ValueError(f"analyzer: residual left-foot diagnostic token: {token}")
    required_right = (
        "grand-bruxelles-civ1-rightfoot-landmark-witness-v1",
        "rightfoot_bone_pose_with_verified_same_skeleton_skin",
        "CIV1_RIGHTFOOT_LANDMARK_OK",
    )
    if not all(token in witness for token in required_right):
        raise ValueError("witness: RightFoot schema/semantic/success token missing")
    required_analysis = (
        "grand-bruxelles-civ1-rightfoot-landmark-raster-analysis-v1",
        "magenta_raster_of_verified_rightfoot_bone_pose",
        "CIV1_RIGHTFOOT_LANDMARK_ANALYSIS_OK",
    )
    if not all(token in analyzer for token in required_analysis):
        raise ValueError("analyzer: RightFoot schema/semantic/success token missing")


def transform(text: str, kind: str) -> str:
    before = text
    if kind == "witness":
        required = (
            "LeftFoot", "RightFoot", "leftfoot_bone_pose_with_verified_same_skeleton_skin",
            POSE_BONES_LINE, ALIASES_BLOCK, BILATERAL_FLOOR_LINE,
        ) + WITNESS_FROZEN
    elif kind == "analyzer":
        required = (
            "LeftFoot", "magenta_raster_of_verified_leftfoot_bone_pose",
        ) + ANALYZER_FROZEN
    else:
        raise ValueError(f"unknown kind: {kind}")
    for token in required:
        if token not in before:
            raise ValueError(f"{kind}: validated upstream token missing: {token}")
    out = _transform_witness(before) if kind == "witness" else _replace_semantic_target(before)
    if out == before:
        raise ValueError(f"{kind}: no semantic transformation applied")
    return out


def build(left_witness: Path, left_analyzer: Path, out_witness: Path, out_analyzer: Path) -> None:
    witness = transform(left_witness.read_text(encoding="utf-8"), "witness")
    analyzer = transform(left_analyzer.read_text(encoding="utf-8"), "analyzer")
    validate_outputs(witness, analyzer)
    out_witness.write_text(witness, encoding="utf-8")
    out_analyzer.write_text(analyzer, encoding="utf-8")


def main(argv: list[str]) -> int:
    try:
        if len(argv) == 4 and argv[1] == "--verify":
            validate_outputs(Path(argv[2]).read_text(encoding="utf-8"), Path(argv[3]).read_text(encoding="utf-8"))
            print("CIV1_RIGHTFOOT_HARNESS_VERIFY_OK")
            return 0
        if len(argv) != 5:
            print("usage: build_civ1_rightfoot_landmark_from_validated_left.py LEFT_WITNESS.gd LEFT_ANALYZER.py OUT_WITNESS.gd OUT_ANALYZER.py\n       build_civ1_rightfoot_landmark_from_validated_left.py --verify RIGHT_WITNESS.gd RIGHT_ANALYZER.py", file=sys.stderr)
            return 2
        build(*map(Path, argv[1:]))
    except Exception as exc:
        print(f"CIV1_RIGHTFOOT_HARNESS_BUILD_FAIL: {exc}", file=sys.stderr)
        return 3
    print("CIV1_RIGHTFOOT_HARNESS_BUILD_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
