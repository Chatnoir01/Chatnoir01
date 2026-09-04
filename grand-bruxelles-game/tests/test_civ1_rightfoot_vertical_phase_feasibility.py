import importlib.util
from pathlib import Path
P=Path(__file__).parents[1]/'tools'/'analyze_civ1_rightfoot_vertical_phase_feasibility.py'
s=importlib.util.spec_from_file_location('m',P); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
def sample(i,sy,ty):
    return {'sample_index':i,'bones':{'RightFoot':{'source':{'model_origin':[0.,sy,0.]},'target':{'model_origin':[0.,ty,0.]}},'Hips':{'source':{'model_origin':[0.,0.,0.]},'target':{'model_origin':[0.,0.,0.]}}}}
def payload(shift=20):
    import math
    src=[math.cos(2*math.pi*i/120) for i in range(121)]
    tgt=[src[(i-shift)%120] for i in range(120)]+[src[(120-shift)%120]]
    return {'rotation_enabled':True,'position_enabled':False,'scale_enabled':False,'model_space_samples':[sample(i,src[i],tgt[i]) for i in range(121)]}
def test_vertical_shift_preserves_horizontal_exactly():
    seq=[[i,10+i,i*2] for i in range(120)]; out=m.shifted_vertical(seq,7)
    assert all(out[i][0]==seq[i][0] and out[i][2]==seq[i][2] for i in range(120))
def test_synthetic_phase_has_viable_oracle_shift():
    r=m.analyze(payload()); assert r['family_feasible']; assert r['viable_shift_count']>0; assert r['best']['horizontal_preserved_exactly']
def test_oracle_is_never_production_candidate():
    r=m.analyze(payload()); assert r['feasibility_oracle_only'] and not r['production_candidate'] and not r['runtime_authorized']
def test_wrong_probe_mode_fails_closed():
    p=payload(); p['position_enabled']=True
    try:m.analyze(p)
    except ValueError as e: assert 'rotation-only' in str(e)
    else: raise AssertionError('expected fail closed')
def test_sample_index_drift_fails_closed():
    p=payload(); p['model_space_samples'][7]['sample_index']=8
    try:m.analyze(p)
    except ValueError as e: assert 'sample index drift' in str(e)
    else: raise AssertionError('expected fail closed')
