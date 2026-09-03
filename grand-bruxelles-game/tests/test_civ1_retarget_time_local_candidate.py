#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("time_local", ROOT / "tools" / "patch_civ1_retarget_time_local_candidate.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)

BASE = '''func _make_shadow_skeleton(original: Skeleton3D) -> Skeleton3D:\n    pass\nvar left_foot_reference_ab = {}\n    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n        var normalized_target_foot_origin := target_right_parent_pose.origin + target_right_parent_pose.basis * normalized_target_local_rest_origin\n'''

for radius in (1, 2, 4):
    out = MOD.transform(BASE, center_sample=59, radius=radius)
    assert out.count(MOD.MARKER) == 1
    assert f"center_sample=59 radius={radius}" in out
    assert "normalized_target_left_local_rest_origin := target_left_local_rest_origin" in out
    assert "right_time_local_distance" in out
    assert "right_time_local_weight" in out
    assert "right_time_local_sample_rest" in out
    assert "time-local candidate changed RightFoot length" in out
    assert "posmod(sample_idx - right_time_local_center" in out

for center, radius in ((-1, 2), (120, 2), (59, 0), (59, 30), (True, 2), (59, True)):
    try:
        MOD.transform(BASE, center_sample=center, radius=radius)
    except ValueError:
        pass
    else:
        raise AssertionError(f"invalid window accepted: center={center!r} radius={radius!r}")

try:
    MOD.transform(BASE.replace("func _make_shadow_skeleton", "func nope"), 59, 2)
except ValueError:
    pass
else:
    raise AssertionError("non-bilateral probe accepted")

try:
    MOD.transform(MOD.transform(BASE, 59, 2), 59, 1)
except ValueError:
    pass
else:
    raise AssertionError("double patch accepted")

try:
    MOD.transform(BASE.replace("        var normalized_target_foot_origin := target_right_parent_pose.origin + target_right_parent_pose.basis * normalized_target_local_rest_origin\n", ""), 59, 2)
except ValueError:
    pass
else:
    raise AssertionError("drifted sample anchor accepted")

print("CIV1_RETARGET_TIME_LOCAL_CANDIDATE_TESTS_OK")
