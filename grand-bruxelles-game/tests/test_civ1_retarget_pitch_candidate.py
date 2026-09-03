#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("pitch", ROOT / "tools" / "patch_civ1_retarget_pitch_candidate.py")
MOD = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MOD)

RIGHT = MOD.RIGHT
LEFT = MOD.LEFT
BASE = "func _make_shadow_skeleton():\n    pass\n# left_foot_reference_ab\n" + RIGHT + LEFT

out = MOD.transform(BASE, 0.5)
assert MOD.MARKER in out
assert "right_pitch_fraction: float = 0.5" in out
assert "right_pitch_raw.normalized() * target_local_rest_origin.length()" in out
assert "normalized_target_left_local_rest_origin := target_left_local_rest_origin" in out
assert RIGHT not in out
assert LEFT not in out

for bad in (0.0, 1.0, -0.1, 1.1, True, "0.5"):
    try:
        MOD.transform(BASE, bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f"invalid fraction accepted: {bad!r}")

try:
    MOD.transform(out, 0.25)
except ValueError:
    pass
else:
    raise AssertionError("double pitch patch accepted")

try:
    MOD.transform(BASE.replace(RIGHT, ""), 0.5)
except ValueError:
    pass
else:
    raise AssertionError("drifted RightFoot anchor accepted")

try:
    MOD.transform(BASE.replace("left_foot_reference_ab", "missing"), 0.5)
except ValueError:
    pass
else:
    raise AssertionError("non-bilateral probe accepted")

print("CIV1_RETARGET_PITCH_CANDIDATE_TEST_OK")
