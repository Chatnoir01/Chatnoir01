#!/usr/bin/env python3
"""Derive a RightFoot contact-window raster harness from the validated RightFoot landmark harness.

Only the diagnostic sample set changes, from the immutable identity samples 114..118 to
the source-derived RightFoot contact-context samples 68..71. Camera, distances, marker,
Skeleton/Skin semantics and quantitative rails remain frozen. QA only.
"""
from __future__ import annotations
import sys
from pathlib import Path

SOURCE_WITNESS = "[114, 115, 116, 117, 118]"
TARGET_WITNESS = "[68, 69, 70, 71]"
SOURCE_ANALYZER = "SAMPLES=(114,115,116,117,118)"
TARGET_ANALYZER = "SAMPLES=(68,69,70,71)"
FROZEN_WITNESS = ("1280", "720", "45.0", "[2.0, 4.0, 8.0]", "MARKER_RADIUS_M := 0.025", "marker_mat.no_depth_test=true", "RightFoot")
FROZEN_ANALYZER = ("DISTANCES=(2,4,8)", "MAX_CENTROID_ERROR_PX=1.5", "MAX_PATH_REL_ERROR=0.25", "rightfoot")


def _replace_exact(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"{label}: expected exactly one source sample token, got {text.count(old)}")
    out = text.replace(old, new, 1)
    if old in out or out.count(new) != 1:
        raise ValueError(f"{label}: sample replacement did not stay exact")
    return out


def build(witness: str, analyzer: str) -> tuple[str, str]:
    for token in FROZEN_WITNESS:
        if token not in witness:
            raise ValueError(f"witness frozen rail missing: {token}")
    for token in FROZEN_ANALYZER:
        if token not in analyzer:
            raise ValueError(f"analyzer frozen rail missing: {token}")
    if "grand-bruxelles-civ1-rightfoot-landmark-witness-v1" not in witness:
        raise ValueError("witness schema drift")
    if "grand-bruxelles-civ1-rightfoot-landmark-raster-analysis-v1" not in analyzer:
        raise ValueError("analyzer schema drift")
    return (
        _replace_exact(witness, SOURCE_WITNESS, TARGET_WITNESS, "witness"),
        _replace_exact(analyzer, SOURCE_ANALYZER, TARGET_ANALYZER, "analyzer"),
    )


def verify(witness: str, analyzer: str) -> None:
    if TARGET_WITNESS not in witness or TARGET_ANALYZER not in analyzer:
        raise ValueError("target contact samples missing")
    if SOURCE_WITNESS in witness or SOURCE_ANALYZER in analyzer:
        raise ValueError("identity sample set leaked into contact harness")
    for token in FROZEN_WITNESS:
        if token not in witness:
            raise ValueError(f"witness frozen rail changed: {token}")
    for token in FROZEN_ANALYZER:
        if token not in analyzer:
            raise ValueError(f"analyzer frozen rail changed: {token}")


def main(argv: list[str]) -> int:
    try:
        if len(argv) == 4 and argv[1] == "--verify":
            verify(Path(argv[2]).read_text(), Path(argv[3]).read_text())
            print("CIV1_RIGHTFOOT_CONTACT_HARNESS_VERIFY_OK")
            return 0
        if len(argv) != 5:
            print("usage: build_civ1_rightfoot_contact_witness.py RIGHT_WITNESS RIGHT_ANALYZER OUT_WITNESS OUT_ANALYZER", file=sys.stderr)
            return 2
        witness, analyzer = build(Path(argv[1]).read_text(), Path(argv[2]).read_text())
        Path(argv[3]).write_text(witness)
        Path(argv[4]).write_text(analyzer)
        verify(witness, analyzer)
    except Exception as exc:
        print(f"CIV1_RIGHTFOOT_CONTACT_HARNESS_FAIL: {exc}", file=sys.stderr)
        return 3
    print("CIV1_RIGHTFOOT_CONTACT_HARNESS_OK samples=68,69,70,71")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
