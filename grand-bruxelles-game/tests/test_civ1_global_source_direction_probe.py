from pathlib import Path
import importlib.util
import pytest

SCRIPT=Path(__file__).parents[1]/'tools'/'patch_civ1_global_source_direction_probe.py'
spec=importlib.util.spec_from_file_location('probe', SCRIPT)
probe=importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)

BASE=(
    'func _make_shadow_skeleton():\n'
    '    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n'
    '    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n'
    '    var left_foot_reference_ab = {}\n'
)


def test_accepts_bounded_partial_blend_and_preserves_left_anchor():
    out=probe.transform(BASE,0.5)
    assert probe.MARKER in out
    assert 'global_source_direction_blend: float = 0.5' in out
    assert 'normalized_target_left_local_rest_origin := target_left_local_rest_origin' in out
    assert 'normalized() * target_local_rest_origin.length()' in out


@pytest.mark.parametrize('value',[0.0,-0.1,1.01,float('nan'),float('inf')])
def test_rejects_invalid_blend(value):
    with pytest.raises(ValueError):
        probe.transform(BASE,value)


def test_rejects_double_patch():
    with pytest.raises(ValueError):
        probe.transform(probe.transform(BASE,0.25),0.5)


def test_rejects_anchor_drift():
    with pytest.raises(ValueError):
        probe.transform(BASE.replace('normalized_target_local_rest_origin','other',1),0.5)


def test_rejects_non_bilateral_probe():
    with pytest.raises(ValueError):
        probe.transform(BASE.replace('left_foot_reference_ab','other'),0.5)
