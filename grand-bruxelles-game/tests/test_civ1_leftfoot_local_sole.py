#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]; TOOL=HERE/'tools'/'analyze_civ1_leftfoot_local_sole.py'; spec=importlib.util.spec_from_file_location('local_sole',TOOL); assert spec and spec.loader; m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def main()->int:
 real_shape={2:[3.564,3.726,3.755,3.774,3.607],4:[3.458,3.680,3.545,3.653,3.725],8:[3.573,3.453,3.745,3.332,3.618]}; good=m.assess_normalized_series(real_shape); assert good['passed'] is True; assert good['distance_mean_relative_spread']<0.05
 switched={2:[3.6]*5,4:[3.5]*5,8:[-3.4]*5}; bad=m.assess_normalized_series(switched); assert bad['passed'] is False and bad['single_side_consistent'] is False
 scaled={2:[3.6]*5,4:[3.5]*5,8:[1.8]*5}; assert m.assess_normalized_series(scaled)['passed'] is False
 text=TOOL.read_text(); assert "identity_anchor':'verified_leftfoot_bone_magenta_landmark'" in text; assert 'ROI_RADIUS_MULT=4.0' in text; assert 'MAX_DISTANCE_MEAN_REL_SPREAD=0.15' in text
 print('CIV1_LEFTFOOT_LOCAL_SOLE_TEST_OK'); return 0
if __name__=='__main__': raise SystemExit(main())
