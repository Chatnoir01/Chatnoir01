import importlib.util, math
from pathlib import Path
P=Path(__file__).parents[1]/'tools'/'analyze_civ1_lowerleg_local_dynamic_sweep.py'
s=importlib.util.spec_from_file_location('m',P); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
def rz(d):
    a=math.radians(d); c=math.cos(a); q=math.sin(a)
    return [[c,-q,0.],[q,c,0.],[0.,0.,1.]]
def angle(r):
    return math.degrees(math.acos(max(-1.,min(1.,(r[0][0]+r[1][1]+r[2][2]-1.)/2.))))
def test_limited_delta_respects_cap(): assert abs(angle(m.limited_delta(rz(20),m.eye(),5))-5)<1e-6
def test_limited_delta_preserves_small_delta(): assert abs(angle(m.limited_delta(rz(3),m.eye(),5))-3)<1e-6
def test_limited_delta_identity_is_identity(): assert angle(m.limited_delta(m.eye(),m.eye(),5))<1e-8
def test_wrong_probe_mode_fails_closed():
    try:m.analyze({'rotation_enabled':False,'position_enabled':False,'scale_enabled':False,'model_space_samples':[]})
    except ValueError as e: assert 'rotation-only' in str(e)
    else: raise AssertionError('expected fail closed')
def test_sample_count_fails_closed():
    try:m.analyze({'rotation_enabled':True,'position_enabled':False,'scale_enabled':False,'model_space_samples':[]})
    except ValueError as e: assert '121' in str(e)
    else: raise AssertionError('expected fail closed')
