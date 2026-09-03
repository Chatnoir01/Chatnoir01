import importlib.util
from pathlib import Path
import pytest
ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/'tools'/'generate_civ1_dynamic_source_direction_candidate.py'
def load():
    spec=importlib.util.spec_from_file_location('g',PATH); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
g=load()
def test_schedule_is_bounded_symmetric_and_fail_closed():
    p=g.generate(8,0.75); s=p['samples']; assert p['center_sample']==59 and len(s)==120; assert s[59]['direction_blend']==pytest.approx(0.75); assert s[58]['direction_blend']==pytest.approx(s[60]['direction_blend']); assert s[50]['direction_blend']==0.0 and s[68]['direction_blend']==0.0; assert p['runtime_authorized'] is False and p['visual_approval_claimed'] is False
def test_taper_decreases_and_rails_are_zero():
    p=g.generate(8,1.0); s=p['samples']; assert all(s[59+d]['direction_blend']>=s[60+d]['direction_blend'] for d in range(0,8)); assert all(x['right_foot_length_error_m']==0.0 and x['left_foot_delta_m']==0.0 for x in s)
@pytest.mark.parametrize('radius,peak',[(1,0.5),(60,0.5),(8,0.0),(8,1.1),(True,0.5),(8,float('nan'))])
def test_rejects_invalid_parameters(radius,peak):
    with pytest.raises(ValueError): g.generate(radius,peak)
