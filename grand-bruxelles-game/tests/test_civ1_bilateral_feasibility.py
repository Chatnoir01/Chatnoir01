import importlib.util, math
from pathlib import Path
P=Path(__file__).parents[1]/'tools'/'analyze_civ1_bilateral_feasibility.py'
s=importlib.util.spec_from_file_location('f',P); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)

def test_inner_and_outer_annulus_are_rejected():
    hip=[0.,0.,0.]; knee=[0.,-2.,0.]; foot=[0.,-3.,0.]
    assert not m.two_bone_reachable(hip,knee,foot,[0.,-0.5,0.])
    assert not m.two_bone_reachable(hip,knee,foot,[0.,-3.5,0.])

def test_two_bone_solution_preserves_lengths():
    r=m.solve_two_bone([0.,0.,0.],[0.,-1.,0.],[0.,-2.,0.],[0.4,-1.8,0.])
    assert r['foot_error_m'] == 0.0
    assert r['upper_length_error_m'] <= 1e-9
    assert r['lower_length_error_m'] <= 1e-9
    assert math.isfinite(r['upper_angle_rad']) and math.isfinite(r['lower_angle_rad'])

def test_smooth_path_obeys_step_limit():
    assert m.smooth_path([[-2,2],[-1,3],[0,4]],1) == [-2,-1,0]

def test_minimal_path_selects_smallest_amplitude(monkeypatch):
    monkeypatch.setattr(m,'allowed_rows',lambda _samples,_seq,_limit:[[-3,3],[-2,2],[-1,1]])
    used,path=m.minimal_path([],[],5,1)
    assert used==3
    assert max(abs(x) for x in path)==3

def test_rotation_only_contract_fails_closed():
    try:m.analyze({'rotation_enabled':False,'position_enabled':False,'scale_enabled':False})
    except ValueError as e: assert 'rotation-only' in str(e)
    else: raise AssertionError('expected fail-closed probe rejection')
