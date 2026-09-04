import importlib.util, math
from pathlib import Path
P=Path(__file__).parents[1]/'tools'/'analyze_civ1_pelvis_compensation.py'
s=importlib.util.spec_from_file_location('m',P); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)

def test_smooth_path_respects_source_step_bound():
    allowed=[]
    for i in range(m.CYCLE):
        center=min(20,i//6)
        allowed.append(list(range(center-2,center+3)))
    path=m._smooth_path(allowed,0.003)
    assert path is not None
    assert max(abs(path[i]-path[i-1]) for i in range(1,len(path)))<=0.003+1e-12

def test_smooth_path_rejects_jump_above_source_motion():
    allowed=[[0] for _ in range(m.CYCLE)]
    allowed[60]=[20]
    assert m._smooth_path(allowed,0.010) is None

def test_smooth_path_rejects_empty_bilateral_reach_set():
    allowed=[[0] for _ in range(m.CYCLE)]
    allowed[33]=[]
    assert m._smooth_path(allowed,0.010) is None

def test_wrong_probe_fails_closed():
    p={'rotation_enabled':True,'position_enabled':True,'scale_enabled':False,'model_space_samples':[]}
    try:m.analyze(p)
    except ValueError as e: assert 'rotation-only' in str(e)
    else: raise AssertionError('expected fail closed')

def test_sample_count_fails_closed():
    p={'rotation_enabled':True,'position_enabled':False,'scale_enabled':False,'model_space_samples':[]}
    try:m.analyze(p)
    except ValueError as e: assert '121' in str(e)
    else: raise AssertionError('expected fail closed')

def test_nonfinite_vector_fails_closed():
    try:m.vec([0.0,float('nan'),0.0],'probe')
    except ValueError as e: assert 'non-finite' in str(e)
    else: raise AssertionError('expected fail closed')
