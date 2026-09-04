import importlib.util, math
from pathlib import Path
P=Path(__file__).parents[1]/'tools'/'analyze_civ1_bilateral_ik.py'
s=importlib.util.spec_from_file_location('ik',P); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)

def test_two_bone_reaches_target_without_stretch():
    hip=[0.,0.,0.]; knee=[0.,-1.,0.]; foot=[0.,-2.,0.]; goal=[0.4,-1.8,0.]
    r=m.solve_two_bone(hip,knee,foot,goal)
    assert r['foot_error_m'] <= 1e-12
    assert r['upper_length_error_m'] <= 1e-9
    assert r['lower_length_error_m'] <= 1e-9
    assert all(math.isfinite(x) for x in r['upper_delta_xyzw']+r['lower_delta_xyzw'])

def test_unreachable_target_rejected():
    try:m.solve_two_bone([0,0,0],[0,-1,0],[0,-2,0],[0,-3,0])
    except ValueError as e: assert 'unreachable' in str(e)
    else: raise AssertionError('expected unreachable rejection')

def test_quaternion_from_to_is_normalized():
    q=m.quat_from_to([1,0,0],[0,1,0])
    assert abs(sum(x*x for x in q)-1.0) < 1e-12
    assert abs(m.qangle(q)-math.pi/2) < 1e-12

def test_robust_path_skips_zero_margin_candidate(monkeypatch):
    monkeypatch.setattr(m,'CAPS_MM',range(55,59))
    def allowed(_samples,_seq,cap): return [[0]]*m.CYCLE if cap>=56 else [[]]+[[0]]*(m.CYCLE-1)
    def smooth(rows,_step):
        if not rows[0]: return None
        cap=56 if rows[0] else 0
        return [0.056]*m.CYCLE
    monkeypatch.setattr(m,'allowed_dys',allowed); monkeypatch.setattr(m,'smooth_path',smooth)
    cap,path,evidence=m.choose_robust_path([],[],0.02)
    assert cap==58
    assert max(abs(x) for x in path)==0.056
    assert [e['margin_mm'] for e in evidence]==[-1,0,1,2]

def test_robust_path_fails_without_margin(monkeypatch):
    monkeypatch.setattr(m,'CAPS_MM',range(55,58))
    monkeypatch.setattr(m,'allowed_dys',lambda _s,_q,_c:[[0]]*m.CYCLE)
    monkeypatch.setattr(m,'smooth_path',lambda _r,_st:[0.056]*m.CYCLE)
    cap,path,evidence=m.choose_robust_path([],[],0.02)
    assert cap is None and path is None
    assert evidence[-1]['margin_mm']==1
