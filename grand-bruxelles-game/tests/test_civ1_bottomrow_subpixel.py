#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]
TOOL=HERE/'tools'/'analyze_civ1_bottomrow_subpixel.py'
spec=importlib.util.spec_from_file_location('subpixel',TOOL); assert spec and spec.loader
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def dm(d,p): return {'distance_m':d,'subpixel_path_px':p}

def main()->int:
    # Fully perspective-consistent control remains accepted.
    s=m.scale_calibration([dm(2,3.0),dm(4,1.5),dm(8,0.75)])
    assert s['near_calibration_passed'] is True
    assert s['far_non_increasing'] is True
    assert s['far_scale_calibration_passed'] is True
    assert s['quantitative_8m_candidate'] is True

    # Non-increasing is necessary but no longer sufficient: this is the real
    # false-positive shape measured by artifact 9983210412.
    s=m.scale_calibration([dm(2,3.78215693299893),dm(4,1.9590022396895392),dm(8,1.688355761885191)])
    assert s['near_calibration_passed'] is True
    assert s['far_non_increasing'] is True
    assert s['far_4_to_8_relative_error'] > m.MAX_FAR_SCALE_REL_ERROR
    assert s['far_scale_calibration_passed'] is False
    assert s['quantitative_8m_candidate'] is False

    # The previously observed integer aliasing shape remains rejected too.
    s=m.scale_calibration([dm(2,3.0),dm(4,1.5),dm(8,2.0)])
    assert s['near_calibration_passed'] is True
    assert s['far_non_increasing'] is False
    assert s['far_scale_calibration_passed'] is False
    assert s['quantitative_8m_candidate'] is False

    # Near-distance calibration failure blocks 8 m even if far scale happens to fit.
    s=m.scale_calibration([dm(2,3.0),dm(4,2.5),dm(8,1.25)])
    assert s['near_calibration_passed'] is False
    assert s['far_scale_calibration_passed'] is True
    assert s['quantitative_8m_candidate'] is False

    assert m.WHITE == 220
    assert m.WEIGHT_FLOOR == 180
    assert m.SUPPORT_PAD_PX == 1
    assert m.MIN_NEAR_WHITE_PIXELS == 15
    assert m.MAX_NEAR_SCALE_REL_ERROR == 0.25
    assert m.MAX_FAR_SCALE_REL_ERROR == 0.25
    assert m.POSITION_ROW_SEMANTIC == 'same_bottom_most_near_white_row'

    text=TOOL.read_text(encoding='utf-8')
    for key in ('"perceptual_2_8m_claimed":False','"planted_contact_claimed":False','"animation_correction_authorized":False','"runtime_authorized":False','"visual_approval_claimed":False','"player_view_claimed":False'):
        assert key in text
    print('CIV1_BOTTOMROW_SUBPIXEL_TEST_OK')
    return 0
if __name__=='__main__': raise SystemExit(main())
