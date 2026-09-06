#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
TOOL = HERE / "tools" / "build_civ1_rightfoot_landmark_from_validated_left.py"
spec = importlib.util.spec_from_file_location("rightfoot_builder", TOOL)
assert spec and spec.loader
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

witness = '''const WIDTH := 1280
const HEIGHT := 720
const VERTICAL_FOV_DEG := 45.0
const PLAYER_DISTANCES_M := [2.0, 4.0, 8.0]
const TARGET_SAMPLES := [114, 115, 116, 117, 118]
const MARKER_RADIUS_M := 0.025
var semantic = "leftfoot_bone_pose_with_verified_same_skeleton_skin"
var bone = "LeftFoot"
marker_mat.no_depth_test=true
print("CIV1_LEFTFOOT_LANDMARK_OK")
'''
analyzer = '''DISTANCES=(2,4,8)
SAMPLES=(114,115,116,117,118)
MAX_CENTROID_ERROR_PX=1.5
MAX_PATH_REL_ERROR=0.25
semantic='magenta_raster_of_verified_leftfoot_bone_pose'
side='LeftFoot'
print('CIV1_LEFTFOOT_LANDMARK_ANALYSIS_OK')
'''

rw = m.transform(witness, "witness")
ra = m.transform(analyzer, "analyzer")
assert "RightFoot" in rw and "rightfoot_bone_pose_with_verified_same_skeleton_skin" in rw
assert "CIV1_RIGHTFOOT_LANDMARK_OK" in rw
assert "magenta_raster_of_verified_rightfoot_bone_pose" in ra
assert "CIV1_RIGHTFOOT_LANDMARK_ANALYSIS_OK" in ra
for frozen in ("1280", "720", "45.0", "[2.0, 4.0, 8.0]", "[114, 115, 116, 117, 118]", "MARKER_RADIUS_M := 0.025", "marker_mat.no_depth_test=true"):
    assert frozen in rw
for frozen in ("DISTANCES=(2,4,8)", "SAMPLES=(114,115,116,117,118)", "MAX_CENTROID_ERROR_PX=1.5", "MAX_PATH_REL_ERROR=0.25"):
    assert frozen in ra

try:
    m.transform(witness.replace("MARKER_RADIUS_M := 0.025", "MARKER_RADIUS_M := 0.03"), "witness")
except ValueError:
    pass
else:
    raise AssertionError("builder must fail closed when validated marker rail drifts")

print("CIV1_RIGHTFOOT_LANDMARK_BUILDER_TEST_OK")
