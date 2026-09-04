import importlib.util, math
from pathlib import Path
P=Path(__file__).parents[1]/'tools'/'analyze_civ1_skeleton_applyability.py'
s=importlib.util.spec_from_file_location('a',P); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)

def test_unit_quaternion_accepts_identity():
    assert m.qfinite_unit([0.0,0.0,0.0,1.0])

def test_unit_quaternion_rejects_bad_norm():
    assert not m.qfinite_unit([0.0,0.0,0.0,2.0])

def test_unit_quaternion_rejects_nonfinite():
    assert not m.qfinite_unit([0.0,0.0,float('nan'),1.0])

def test_cycle_constant_is_full_120_samples():
    assert m.CYCLE == 120

def test_eps_is_strict():
    assert m.EPS < 1e-6
