#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parents[1]
TOOL=HERE/'tools'/'analyze_civ1_leftfoot_landmark_raster.py'
spec=importlib.util.spec_from_file_location('leftfoot_landmark',TOOL)
assert spec and spec.loader
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


def main()->int:
    good=m.assess([100.0,101.0,103.0,104.0,106.0],[100.2,101.2,103.1,104.1,106.1])
    assert good['passed'] is True and good['direction_match'] is True
    flipped=m.assess([106.0,104.0,103.0,101.0,100.0],[100.0,101.0,103.0,104.0,106.0])
    assert flipped['passed'] is False and flipped['direction_match'] is False
    drift=m.assess([100.0,101.0,104.0,107.0,110.0],[100.0,101.0,102.0,103.0,104.0])
    assert drift['passed'] is False and drift['max_centroid_error_px']>m.MAX_CENTROID_ERROR_PX
    text=TOOL.read_text(encoding='utf-8')
    assert "landmark_semantic':'magenta_raster_of_verified_leftfoot_bone_pose'" in text
    assert 'MAX_CENTROID_ERROR_PX=1.5' in text
    assert 'MAX_PATH_REL_ERROR=0.25' in text
    for key in (
        "'perceptual_2_8m_claimed':False",
        "'planted_contact_claimed':False",
        "'animation_correction_authorized':False",
        "'runtime_authorized':False",
        "'visual_approval_claimed':False",
        "'player_view_claimed':False",
    ):
        assert key in text
    witness=(HERE/'tools'/'godot_civ1_leftfoot_landmark_witness.gd').read_text(encoding='utf-8')
    assert 'leftfoot_bone_pose_with_verified_same_skeleton_skin' in witness
    assert 'skeleton.get_bone_global_pose(int(mapping["LeftFoot"]))' in witness
    assert '_collect_mesh_integrity(body,skeleton,integrity)' in witness
    assert 'same_skeleton_skin_count' in witness
    assert 'MARKER_RADIUS_M := 0.025' in witness
    # The bone-centred marker is intentionally diagnostic and may sit inside the shoe.
    # It must render through the mesh rather than moving away from the actual LeftFoot pose.
    assert 'marker_mat.no_depth_test=true' in witness
    assert '"marker_no_depth_test":true' in witness
    print('CIV1_LEFTFOOT_LANDMARK_TEST_OK')
    return 0

if __name__=='__main__': raise SystemExit(main())
