import importlib.util
from pathlib import Path
P=Path(__file__).parents[1]/'tools'/'analyze_civ1_fixed_length_reconstruction.py'
s=importlib.util.spec_from_file_location('a',P); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)

def test_fixed_solver_preserves_supplied_segment_lengths_after_hip_move():
    hip=[0.0,0.2,0.0]; knee=[0.0,-1.0,0.0]; foot=[0.0,-2.0,0.0]; goal=[0.2,-1.7,0.0]
    r=m.solve_fixed(hip,knee,foot,goal,1.0,1.0)
    assert r['upper_length_error_m'] < 1e-9
    assert r['lower_length_error_m'] < 1e-9

def test_fixed_reachability_rejects_inner_annulus():
    assert not m.fixed_reachable([0,0,0],[0.5,0,0],2.0,1.0)

def test_fixed_reachability_rejects_outer_annulus():
    assert not m.fixed_reachable([0,0,0],[3.1,0,0],2.0,1.0)

def test_correction_continuity_does_not_blame_preexisting_source_wrap():
    sols=[]
    for i in range(m.CYCLE):
        ref=[0.0,0.0,0.0] if i<119 else [0.0,1.0,0.0]
        sols.append({'knee':ref[:],'knee_ref':ref[:],'upper_angle_rad':0.0,'lower_angle_rad':0.0})
    knee_step,joint_step=m.correction_continuity(sols)
    assert knee_step == 0.0
    assert joint_step == 0.0

def test_correction_continuity_detects_added_spike():
    sols=[{'knee':[0.0,0.0,0.0],'knee_ref':[0.0,0.0,0.0],'upper_angle_rad':0.0,'lower_angle_rad':0.0} for _ in range(m.CYCLE)]
    sols[20]['knee']=[0.08,0.0,0.0]
    knee_step,_=m.correction_continuity(sols)
    assert knee_step >= 0.08

def _state(mm, correction=0.0, angle=0.0):
    leg={'knee':[correction,0.0,0.0],'knee_ref':[0.0,0.0,0.0],'upper_angle_rad':angle,'lower_angle_rad':angle,'upper_length_error_m':0.0,'lower_length_error_m':0.0}
    return {'mm':mm,'right':dict(leg),'left':dict(leg)}

def test_continuous_cycle_requires_119_to_0_wrap_pass():
    rows=[{0:_state(0)} for _ in range(m.CYCLE)]
    rows[-1]={0:_state(0,correction=0.08)}
    assert m.continuous_cycle(rows,10) is None

def test_continuous_cycle_finds_path_inside_unchanged_rails():
    rows=[{0:_state(0)} for _ in range(m.CYCLE)]
    cap,path=m.continuous_cycle(rows,10)
    assert cap == 0
    assert path == [0]*m.CYCLE

def test_transition_rejects_joint_step_above_12_degrees():
    assert not m.transition_ok(_state(0,angle=0.0),_state(0,angle=m.MAX_JOINT_STEP_RAD+0.01),10)

def test_probe_contract_is_rotation_only():
    try:
        m.analyze({'rotation_enabled':False,'position_enabled':False,'scale_enabled':False})
    except ValueError as e:
        assert 'rotation-only' in str(e)
    else:
        raise AssertionError('expected fail-closed rotation-only rejection')
