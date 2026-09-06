#!/usr/bin/env python3
"""Build an independent RightFoot diagnostic witness from the validated LeftFoot harness.

Only semantic-side tokens are transformed. The frozen camera, marker, Skin/Skeleton,
source, and raster thresholds are intentionally untouched. This is QA infrastructure,
not runtime code.
"""
from __future__ import annotations
import sys
from pathlib import Path

REPLACEMENTS = (
    ("LEFTFOOT", "RIGHTFOOT"),
    ("LeftFoot", "RightFoot"),
    ("leftfoot", "rightfoot"),
    ("DiagnosticLeftFootLandmark", "DiagnosticRightFootLandmark"),
)


def transform(text: str, kind: str) -> str:
    before = text
    required = {
        "witness": ("LeftFoot", "leftfoot_bone_pose_with_verified_same_skeleton_skin", "MARKER_RADIUS_M := 0.025", "marker_mat.no_depth_test=true"),
        "analyzer": ("LeftFoot", "MAX_CENTROID_ERROR_PX=1.5", "MAX_PATH_REL_ERROR=0.25", "magenta_raster_of_verified_leftfoot_bone_pose"),
    }[kind]
    for token in required:
        if token not in before:
            raise ValueError(f"{kind}: validated upstream token missing: {token}")
    out = before
    # Longest/specific replacements first, then generic semantic casing.
    for old, new in REPLACEMENTS:
        out = out.replace(old, new)
    if out == before:
        raise ValueError(f"{kind}: no semantic transformation applied")
    forbidden = ("LeftFoot", "leftfoot", "LEFTFOOT")
    residual = [token for token in forbidden if token in out]
    if residual:
        raise ValueError(f"{kind}: residual left-foot semantic tokens: {residual}")
    # Frozen evidence rails must survive byte-semantically.
    frozen = (
        "1280", "720", "45.0", "[2.0, 4.0, 8.0]", "[114, 115, 116, 117, 118]"
    ) if kind == "witness" else (
        "DISTANCES=(2,4,8)", "SAMPLES=(114,115,116,117,118)",
        "MAX_CENTROID_ERROR_PX=1.5", "MAX_PATH_REL_ERROR=0.25",
    )
    for token in frozen:
        if token not in out:
            raise ValueError(f"{kind}: frozen rail changed or missing: {token}")
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
