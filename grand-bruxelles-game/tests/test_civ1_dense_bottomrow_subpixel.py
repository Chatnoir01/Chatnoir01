#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]; TOOL=HERE/'tools'/'analyze_civ1_dense_bottomrow_subpixel.py'
spec=importlib.util.spec_from_file_location('dense',TOOL); assert spec and spec.loader
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def dm(d,p): return {'distance_m':d,'subpixel_path_px':p}
def main()->int:
    assert m.SAMPLES==tuple(range(111,120)); assert m.MIN_COMMON_SAMPLES==7; assert m.MAX_SCALE_REL_ERROR==0.25
    sparse=m._load_sparse(); assert callable(sparse.observation); assert sparse.MIN_NEAR_WHITE_PIXELS==15
    # Reproduces the real dense failure shape: 8m/111 and 2m/119 are under-sampled.
    common=set(m.SAMPLES)-{111,119}
    assert m.longest_contiguous(common)==list(range(112,119))
    assert len(m.longest_contiguous(common))==7
    # A split set must choose the longest contiguous run, never bridge a gap.
    assert m.longest_contiguous({111,112,114,115,116,117})==[114,115,116,117]
    s=m.scale_calibration([dm(2,8.0),dm(4,4.0),dm(8,2.0)])
    assert s['near_calibration_passed'] and s['far_scale_calibration_passed'] and s['quantitative_8m_candidate']
    s=m.scale_calibration([dm(2,8.0),dm(4,4.0),dm(8,3.2)])
    assert s['near_calibration_passed'] and not s['far_scale_calibration_passed'] and not s['quantitative_8m_candidate']
    text=TOOL.read_text(encoding='utf-8')
    assert 'MIN_COMMON_SAMPLES=7' in text
    assert "'selected_common_samples':window" in text
    for key in ('perceptual_2_8m_claimed','planted_contact_claimed','animation_correction_authorized','runtime_authorized','visual_approval_claimed','player_view_claimed'):
        assert f"'{key}':False" in text
    print('CIV1_DENSE_BOTTOMROW_COMMON_WINDOW_TEST_OK')
    return 0
if __name__=='__main__': raise SystemExit(main())