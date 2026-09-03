#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("axis", ROOT / "tools" / "patch_civ1_retarget_axis_candidate.py")
MOD = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MOD)
BASE = '''func _make_shadow_skeleton(original: Skeleton3D) -> Skeleton3D:\n    pass\nvar left_foot_reference_ab = {}\n    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n'''

for mode in sorted(MOD.MODES):
    out = MOD.transform(BASE, mode)
    assert out.count(MOD.MARKER) == 1
    assert "normalized_target_left_local_rest_origin := target_left_local_rest_origin" in out
    assert "sqrt(max(0.0, right_axis_y_sq))" in out
    assert "axis candidate exceeds preserved RightFoot length" in out
assert "right_axis_use_x: bool = true" in MOD.transform(BASE, "right_x")
assert "right_axis_use_z: bool = false" in MOD.transform(BASE, "right_x")
assert "right_axis_use_x: bool = false" in MOD.transform(BASE, "right_z")
assert "right_axis_use_z: bool = true" in MOD.transform(BASE, "right_z")
assert "right_axis_use_x: bool = true" in MOD.transform(BASE, "right_xz")
assert "right_axis_use_z: bool = true" in MOD.transform(BASE, "right_xz")
for bad in ("", "left_x", "RIGHT_Z"):
    try: MOD.transform(BASE, bad)
    except ValueError: pass
    else: raise AssertionError("bad mode accepted")
try: MOD.transform(BASE.replace("func _make_shadow_skeleton", "func nope"), "right_z")
except ValueError: pass
else: raise AssertionError("non-bilateral probe accepted")
try: MOD.transform(MOD.transform(BASE, "right_z"), "right_x")
except ValueError: pass
else: raise AssertionError("double patch accepted")
print("CIV1_RETARGET_AXIS_CANDIDATE_TESTS_OK")
