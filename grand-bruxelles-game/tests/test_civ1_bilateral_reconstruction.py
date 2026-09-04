import importlib.util, math
from pathlib import Path
P=Path(__file__).parents[1]/'tools'/'analyze_civ1_bilateral_reconstruction.py'
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

def test_continuity_metrics_close_cycle():
    base={'upper_angle_rad':0.0,'lower_angle_rad':0.0}
    sols=[dict(base,knee=[0.,-1.,0.]) for _ in range(m.CYCLE)]
    sols[-1]=dict(base,knee=[0.01,-1.,0.])
    k,j=m.continuity_metrics(sols)
    assert abs(k-0.01)<1e-12 and j==0.0

def test_continuity_detects_joint_spike():
    sols=[]
    for i in range(m.CYCLE):
        sols.append({'knee':[0.,-1.,0.],'upper_angle_rad':0.0 if i!=60 else math.radians(20),'lower_angle_rad':0.0})
    _,j=m.continuity_metrics(sols)
    assert j > m.MAX_JOINT_STEP_RAD

def test_smooth_path_obeys_step_limit():
    assert m.smooth_path([[-2,2],[-1,3],[0,4]],1) == [-2,-1,0]

def test_rotation_only_contract_fails_closed():
    try:m.analyze({'rotation_enabled':False,'position_enabled':False,'scale_enabled':False})
    except ValueError as e: assert 'rotation-only' in str(e)
    else: raise AssertionError('expected fail-closed probe rejection')
