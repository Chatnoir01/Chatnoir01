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
const POSE_BONES := ["Hips", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
const ALIASES := {
    "Hips":["hips","pelvis"], "RightUpperLeg":["rightupperleg","rightupleg","rupperleg"],
    "RightLowerLeg":["rightlowerleg","rightleg","rlowerleg"], "RightFoot":["rightfoot","rfoot"],
    "LeftUpperLeg":["leftupperleg","leftupleg","lupperleg"], "LeftLowerLeg":["leftlowerleg","leftleg","llowerleg"],
    "LeftFoot":["leftfoot","lfoot"]
}
const MARKER_RADIUS_M := 0.025
func run(frames,mapping,skeleton):
    var bilateral_floor_y:=INF
    for frame in frames:
        bilateral_floor_y=min(bilateral_floor_y,_frame_pose(frame,"LeftFoot").origin.y,_frame_pose(frame,"RightFoot").origin.y)
    var left_local:=skeleton.get_bone_global_pose(int(mapping["LeftFoot"])).origin
    var left_world:=skeleton.to_global(left_local)
    marker.global_position=left_world
    marker_mat.no_depth_test=true
    print("leftfoot_bone_pose_with_verified_same_skeleton_skin")
    print("leftfoot_bone_name", mapping["LeftFoot"])
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

# The exact prior failure: global replacement collapsed both ALIASES entries into
# duplicate RightFoot keys. Structural bilateral declarations must remain intact.
assert rw.count('"RightFoot":["rightfoot","rfoot"]') == 1
assert rw.count('"LeftFoot":["leftfoot","lfoot"]') == 1
assert m.POSE_BONES_LINE in rw
assert m.ALIASES_BLOCK in rw
assert m.BILATERAL_FLOOR_LINE in rw

# Only the diagnostic target moves to the right side.
assert 'mapping["RightFoot"]' in rw
assert 'rightfoot_bone_pose_with_verified_same_skeleton_skin' in rw
assert 'rightfoot_bone_name' in rw
assert 'CIV1_RIGHTFOOT_LANDMARK_OK' in rw
assert 'magenta_raster_of_verified_rightfoot_bone_pose' in ra
assert 'CIV1_RIGHTFOOT_LANDMARK_ANALYSIS_OK' in ra

for frozen in ("1280", "720", "45.0", "[2.0, 4.0, 8.0]", "[114, 115, 116, 117, 118]", "MARKER_RADIUS_M := 0.025", "marker_mat.no_depth_test=true"):
    assert frozen in rw
for frozen in ("DISTANCES=(2,4,8)", "SAMPLES=(114,115,116,117,118)", "MAX_CENTROID_ERROR_PX=1.5", "MAX_PATH_REL_ERROR=0.25"):
    assert frozen in ra

# Fail closed if any validated structural or raster rail drifts.
for broken in (
    witness.replace('"LeftFoot":["leftfoot","lfoot"]', '"LeftFoot":["lf"]'),
    witness.replace("MARKER_RADIUS_M := 0.025", "MARKER_RADIUS_M := 0.03"),
):
    try:
        m.transform(broken, "witness")
    except ValueError:
        pass
    else:
        raise AssertionError("builder must fail closed on validated upstream drift")

print("CIV1_RIGHTFOOT_LANDMARK_BUILDER_TEST_OK")
