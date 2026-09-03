#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("blend", ROOT / "tools" / "patch_civ1_retarget_blend_candidate.py")
MOD = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MOD)

PREFIX = "func _make_shadow_skeleton(original: Skeleton3D) -> Skeleton3D:\n    pass\nleft_foot_reference_ab = {}\n"
RIGHT = MOD.RIGHT
LEFT = MOD.LEFT


def expect_error(text, blend):
    try: MOD.transform(text, blend)
    except ValueError: return
    raise AssertionError("expected fail-closed ValueError")


def main():
    source = PREFIX + RIGHT + LEFT
    out = MOD.transform(source, 0.5)
    assert out.count(MOD.MARKER) == 1
    assert "right_candidate_blend: float = 0.5" in out
    assert "left_candidate_blend: float = 0.5" in out
    assert "* target_local_rest_origin.length()" in out
    assert "* target_left_local_rest_origin.length()" in out
    expect_error(source, 0.0); expect_error(source, 1.0); expect_error(source, -0.1)
    expect_error(PREFIX + LEFT, 0.5)
    expect_error(out, 0.5)
    expect_error(source + RIGHT, 0.5)
    print("CIV1_RETARGET_BLEND_CANDIDATE_TEST_OK")
    return 0

if __name__ == "__main__": raise SystemExit(main())
