import importlib.util, math
from pathlib import Path
P=Path(__file__).parents[1]/'tools'/'analyze_civ1_vertical_phase_reachability.py'
s=importlib.util.spec_from_file_location('m',P); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
def payload():
    rows=[]
    for i in range(121):
        a=2*math.pi*(i%120)/120; at=2*math.pi*((i-20)%120)/120
        def side(y):
            return {'model_origin':[0.0,y,0.0]}
        bones={
          'Hips':{'source':side(0),'target':side(0)},
          'RightUpperLeg':{'source':side(0),'target':side(0)},
          'RightLowerLeg':{'source':side(-0.5),'target':side(-0.5)},
          'RightFoot':{'source':side(-0.9+0.1*math.cos(a)),'target':side(-0.9+0.1*math.cos(at))},
        }
        rows.append({'sample_index':i,'bones':bones})
    return {'rotation_enabled':True,'position_enabled':False,'scale_enabled':False,'model_space_samples':rows}
def test_fixed_pelvis_family_rejects_unreachable_phase_fix():
    r=m.analyze(payload()); assert r['baseline_phase_delta_samples']!=0; assert r['viable_shift_count']==0; assert r['verdict']=='JETER_FIXED_PELVIS_VERTICAL_PHASE_FAMILY'; assert any(x['unreachable_sample_count']>0 for x in r['rows'])
def test_wrong_probe_fails_closed():
    p=payload(); p['position_enabled']=True
    try:m.analyze(p)
    except ValueError as e: assert 'rotation-only' in str(e)
    else: raise AssertionError('expected fail closed')
def test_sample_count_fails_closed():
    p=payload(); p['model_space_samples'].pop()
    try:m.analyze(p)
    except ValueError as e: assert '121' in str(e)
    else: raise AssertionError('expected fail closed')
def test_sample_index_drift_fails_closed():
    p=payload(); p['model_space_samples'][7]['sample_index']=8
    try:m.analyze(p)
    except ValueError as e: assert 'sample index drift' in str(e)
    else: raise AssertionError('expected fail closed')
def test_nonfinite_origin_fails_closed():
    p=payload(); p['model_space_samples'][0]['bones']['RightFoot']['target']['model_origin'][1]=float('nan')
    try:m.analyze(p)
    except ValueError as e: assert 'non-finite' in str(e)
    else: raise AssertionError('expected fail closed')
