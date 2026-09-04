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

def test_solver_preserves_bend_side_when_possible():
    hip=[0.,0.,0.]; knee=[0.2,-1.,0.1]; foot=[0.,-2.,0.]; goal=[0.3,-1.8,0.2]
    r=m.solve_two_bone(hip,knee,foot,goal)
    assert m.dist(r['knee'],knee) < m.dist(m.mul(r['knee'],-1),knee)

def test_unreachable_target_rejected():
    try:m.solve_two_bone([0,0,0],[0,-1,0],[0,-2,0],[0,-3,0])
    except ValueError as e: assert 'unreachable' in str(e)
    else: raise AssertionError('expected unreachable rejection')

def test_zero_segment_rejected():
    try:m.solve_two_bone([0,0,0],[0,0,0],[0,-1,0],[0,-0.5,0])
    except ValueError: pass
    else: raise AssertionError('expected zero-vector rejection')

def test_quaternion_from_to_is_normalized():
    q=m.quat_from_to([1,0,0],[0,1,0])
    assert abs(sum(x*x for x in q)-1.0) < 1e-12
    assert abs(m.qangle(q)-math.pi/2) < 1e-12
