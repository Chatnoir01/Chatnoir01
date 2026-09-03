import copy, importlib.util
from pathlib import Path
import pytest
ROOT=Path(__file__).resolve().parents[1]
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
g=load(ROOT/'tools'/'generate_civ1_dynamic_source_direction_candidate.py','g'); p=load(ROOT/'tools'/'patch_civ1_dynamic_source_direction_probe.py','p')
BASE=('func _make_shadow_skeleton():\n' '    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n' '    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n' '    var left_foot_reference_ab = {}\n' '        var normalized_target_foot_origin := target_right_parent_pose.origin + target_right_parent_pose.basis * normalized_target_local_rest_origin\n')
def test_transform_blends_full_direction_preserves_length_and_leftfoot():
    out=p.transform(BASE,g.generate(8,0.75)); assert 'CIV1_DYNAMIC_SOURCE_DIRECTION_NATIVE_PROBE' in out; assert 'target_local_rest_origin.lerp(right_dynamic_source_rest, right_dynamic_blend)' in out; assert '.normalized() * right_dynamic_length' in out; assert 'normalized_target_left_local_rest_origin := target_left_local_rest_origin' in out
def test_rejects_claims_forged_baseline_outside_window_and_rails():
    base=g.generate(8,0.5)
    for mutate in (lambda x:x.__setitem__('runtime_authorized',True),lambda x:x.__setitem__('baseline_source_plant_sample',58),lambda x:x['samples'][0].__setitem__('direction_blend',0.1),lambda x:x['samples'][59].__setitem__('right_foot_length_error_m',1.1e-6),lambda x:x['samples'][59].__setitem__('left_foot_delta_m',1.1e-9)):
        f=copy.deepcopy(base); mutate(f)
        with pytest.raises(ValueError): p.transform(BASE,f)
def test_rejects_static_outward_growing_anchor_drift_and_double_patch():
    f=g.generate(8,0.5)
    for i,s in enumerate(f['samples']):
        d=min((i-59)%120,(59-i)%120); s['direction_blend']=0.5 if d<=8 else 0.0
    with pytest.raises(ValueError): p.transform(BASE,f)
    f=g.generate(8,0.5); f['samples'][60]['direction_blend']=f['samples'][59]['direction_blend']+0.01
    with pytest.raises(ValueError): p.transform(BASE,f)
    with pytest.raises(ValueError): p.transform(BASE.replace('left_foot_reference_ab','left_ref_drift'),g.generate(8,0.5))
    out=p.transform(BASE,g.generate(8,0.5))
    with pytest.raises(ValueError): p.transform(out,g.generate(8,0.5))
