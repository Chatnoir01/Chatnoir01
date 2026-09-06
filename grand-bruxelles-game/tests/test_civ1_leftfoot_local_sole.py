#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parents[1]
TOOL=HERE/'tools'/'analyze_civ1_leftfoot_local_sole.py'
spec=importlib.util.spec_from_file_location('local_sole',TOOL)
assert spec and spec.loader
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


def main()->int:
    # Reproduces the normalized bone-local sole signature measured from the prior
    # exact-head GREEN 15-raster artifact. The three distance means differ by ~4%.
    real_shape={
        2:[3.564,3.726,3.755,3.774,3.607],
        4:[3.458,3.680,3.545,3.653,3.725],
        8:[3.573,3.453,3.745,3.332,3.618],
    }
    good=m.assess_normalized_series(real_shape)
    assert good['passed'] is True
    assert good['single_side_consistent'] is True
    assert good['distance_mean_relative_spread']<0.05

    # A distance-dependent switch to another side/body region must fail closed.
    switched={2:[3.6]*5,4:[3.5]*5,8:[-3.4]*5}
    bad=m.assess_normalized_series(switched)
    assert bad['passed'] is False and bad['single_side_consistent'] is False

    # Same-side but grossly different projected geometry is also not the same local sole signature.
    scaled={2:[3.6]*5,4:[3.5]*5,8:[1.8]*5}
    bad2=m.assess_normalized_series(scaled)
    assert bad2['passed'] is False
    assert bad2['distance_mean_relative_spread']>m.MAX_DISTANCE_MEAN_REL_SPREAD

    text=TOOL.read_text(encoding='utf-8')
    assert "identity_anchor':'verified_leftfoot_bone_magenta_landmark'" in text
    assert "pixel_semantic':'near_white_lowest_row_inside_marker_scaled_roi'" in text
    assert 'ROI_RADIUS_MULT=4.0' in text
    assert 'MAX_DISTANCE_MEAN_REL_SPREAD=0.15' in text
    assert 'MAX_WITHIN_DISTANCE_REL_DEVIATION=0.15' in text
    assert "'quantitative_foot_slide_candidate':False" in text
    for key in (
        "'perceptual_2_8m_claimed':False",
        "'planted_contact_claimed':False",
        "'animation_correction_authorized':False",
        "'runtime_authorized':False",
        "'visual_approval_claimed':False",
        "'player_view_claimed':False",
    ):
        assert key in text
    print('CIV1_LEFTFOOT_LOCAL_SOLE_TEST_OK')
    return 0

if __name__=='__main__': raise SystemExit(main())
