#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]
TOOL=HERE/'tools'/'analyze_civ1_dense_bottomrow_subpixel.py'
spec=importlib.util.spec_from_file_location('dense',TOOL); assert spec and spec.loader
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def dm(d,p): return {'distance_m':d,'subpixel_path_px':p}

def main()->int:
    assert m.SAMPLES==tuple(range(111,120)) and len(m.SAMPLES)==9
    assert m.MAX_SCALE_REL_ERROR==0.25
    sparse=m._load_sparse()
    assert callable(sparse.observation)
    assert sparse.POSITION_ROW_SEMANTIC=='same_bottom_most_near_white_row'

    s=m.scale_calibration([dm(2,8.0),dm(4,4.0),dm(8,2.0)])
    assert s['near_calibration_passed'] is True
    assert s['far_scale_calibration_passed'] is True
    assert s['quantitative_8m_candidate'] is True

    s=m.scale_calibration([dm(2,8.0),dm(4,4.0),dm(8,3.2)])
    assert s['near_calibration_passed'] is True
    assert s['far_scale_calibration_passed'] is False
    assert s['quantitative_8m_candidate'] is False

    s=m.scale_calibration([dm(2,8.0),dm(4,6.0),dm(8,3.0)])
    assert s['near_calibration_passed'] is False
    assert s['quantitative_8m_candidate'] is False

    text=TOOL.read_text(encoding='utf-8')
    assert 'sparse.observation(path)' in text
    for key in ('perceptual_2_8m_claimed','planted_contact_claimed','animation_correction_authorized','runtime_authorized','visual_approval_claimed','player_view_claimed'):
        assert f"'{key}':False" in text
    print('CIV1_DENSE_BOTTOMROW_SUBPIXEL_TEST_OK')
    return 0
if __name__=='__main__': raise SystemExit(main())
