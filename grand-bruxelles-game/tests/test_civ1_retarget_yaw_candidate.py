#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("yaw", ROOT / "tools" / "patch_civ1_retarget_yaw_candidate.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)

BASE = '''func _make_shadow_skeleton(original: Skeleton3D) -> Skeleton3D:\n    pass\nvar left_foot_reference_ab = {}\n    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n'''

for fraction in (0.25, 0.5, 0.75):
    out = MOD.transform(BASE, fraction)
    assert out.count(MOD.MARKER) == 1
    assert f"fraction={fraction:.6f}" in out
    assert "normalized_target_left_local_rest_origin := target_left_local_rest_origin" in out
    assert "right_yaw_horizontal_radius" in out
    assert "right_yaw_delta" in out
    assert "right_yaw_candidate.length()" in out
    assert "yaw candidate changed RightFoot length" in out
    assert "yaw candidate changed RightFoot local Y" in out

for bad in (0.0, 1.0, -0.25, 1.25, float("nan"), float("inf")):
    try:
        MOD.transform(BASE, bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f"bad fraction accepted: {bad}")

try:
    MOD.transform(BASE.replace("func _make_shadow_skeleton", "func nope"), 0.5)
except ValueError:
    pass
else:
    raise AssertionError("non-bilateral probe accepted")

try:
    MOD.transform(MOD.transform(BASE, 0.5), 0.25)
except ValueError:
    pass
else:
    raise AssertionError("double patch accepted")

try:
    MOD.transform(BASE.replace("    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n", ""), 0.5)
except ValueError:
    pass
else:
    raise AssertionError("drifted RightFoot anchor accepted")

print("CIV1_RETARGET_YAW_CANDIDATE_TESTS_OK")
