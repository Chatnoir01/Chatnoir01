import importlib.util, math
from pathlib import Path

MOD_PATH=Path(__file__).resolve().parents[1]/'tools'/'analyze_civ1_lowerleg_basis_sweep.py'
spec=importlib.util.spec_from_file_location('basis',MOD_PATH); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


def qz(a):
    return [0.0,0.0,math.sin(a/2.0),math.cos(a/2.0)]


def rot(q,v):
    return m.mul(m.mat(q),v)


def payload(offset=math.radians(30.0)):
    samples=[]; rest=[0.42,0.0,0.0]
    for i in range(121):
        theta=2.0*math.pi*(i%120)/120.0
        qs=qz(theta); qt=qz(theta+offset)
        so=[0.0,0.0,0.0]; to=[0.0,0.0,0.0]; hips=[0.0,0.0,0.0]
        sf=rot(qs,rest); tf=rot(qt,rest)
        samples.append({'sample_index':i,'bones':{
            'RightLowerLeg':{'source':{'model_origin':so,'model_rotation_xyzw':qs},'target':{'model_origin':to,'model_rotation_xyzw':qt}},
            'RightFoot':{'source':{'model_origin':sf},'target':{'model_origin':tf}},
            'Hips':{'source':{'model_origin':hips},'target':{'model_origin':hips}}
        }})
    return {'rotation_enabled':True,'position_enabled':False,'scale_enabled':False,'model_space_samples':samples}


def test_static_basis_recovers_known_fixed_offset_without_temporal_resampling():
    r=m.analyze(payload())
    assert r['temporal_resampling_used'] is False
    assert r['foot_link_rest_preserved'] is True
    assert r['baseline_phase_delta_samples'] != 0
    assert r['family_viable'] is True
    assert r['viable_anchor_count'] > 0
    assert abs(r['best']['phase_delta_samples']) < abs(r['baseline_phase_delta_samples'])


def test_requires_rotation_only_probe():
    p=payload(); p['position_enabled']=True
    try:m.analyze(p)
    except ValueError as e: assert 'rotation-only' in str(e)
    else: raise AssertionError('expected rejection')


def test_rejects_sample_drift():
    p=payload(); p['model_space_samples'][33]['sample_index']=34
    try:m.analyze(p)
    except ValueError as e: assert 'sample index drift' in str(e)
    else: raise AssertionError('expected rejection')


def test_rejects_non_finite_rotation():
    p=payload(); p['model_space_samples'][5]['bones']['RightLowerLeg']['target']['model_rotation_xyzw'][0]=float('nan')
    try:m.analyze(p)
    except ValueError as e: assert 'non-finite' in str(e)
    else: raise AssertionError('expected rejection')


def test_rejects_rest_drift():
    p=payload(); p['model_space_samples'][20]['bones']['RightFoot']['target']['model_origin'][0]+=0.01
    try:m.analyze(p)
    except ValueError as e: assert 'target rest drift' in str(e)
    else: raise AssertionError('expected rejection')
