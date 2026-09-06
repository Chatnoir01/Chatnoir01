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
    # Calibrated perspective control: halving with doubled distance is accepted.
    s=m.scale_calibration([dm(2,3.0),dm(4,1.5),dm(8,0.75)])
    assert s['near_calibration_passed'] is True
    assert s['far_non_increasing'] is True
    assert s['quantitative_8m_candidate'] is True
    # The previously observed aliased shape remains rejected.
    s=m.scale_calibration([dm(2,3.0),dm(4,1.5),dm(8,2.0)])
    assert s['near_calibration_passed'] is True
    assert s['far_non_increasing'] is False
    assert s['quantitative_8m_candidate'] is False
    # Near-distance calibration failure blocks 8 m even if 8 m happens to decrease.
    s=m.scale_calibration([dm(2,3.0),dm(4,2.5),dm(8,1.0)])
    assert s['near_calibration_passed'] is False
    assert s['quantitative_8m_candidate'] is False
    text=TOOL.read_text(encoding='utf-8')
    assert 'WHITE=220' in text and 'WEIGHT_FLOOR=180' in text and 'SUPPORT_PAD_PX=1' in text
    assert 'same bottom-most row' in text
    for key in ('"perceptual_2_8m_claimed":False','"planted_contact_claimed":False','"animation_correction_authorized":False','"runtime_authorized":False','"visual_approval_claimed":False','"player_view_claimed":False'):
        assert key in text
    print('CIV1_BOTTOMROW_SUBPIXEL_TEST_OK')
    return 0
if __name__=='__main__': raise SystemExit(main())
