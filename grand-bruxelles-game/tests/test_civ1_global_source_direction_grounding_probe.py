from pathlib import Path
import importlib.util
import pytest
SCRIPT=Path(__file__).parents[1]/'tools'/'patch_civ1_global_source_direction_grounding_probe.py'
spec=importlib.util.spec_from_file_location('probe',SCRIPT); probe=importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
BASE=(
'func _make_shadow_skeleton():\n'
'    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n'
'    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n'
'    var left_foot_reference_ab = {}\n'
'    var model_space_samples: Array[Dictionary] = []\n'
'        normalized_target_right_foot_y.append(normalized_hips_relative.y)\n'
'    var phase_vertical_summary := _vertical_phase_summary(model_space_samples, animation.length)\n'
'    var right_foot_reference_ab := _reference_ab_summary(\n'
'        phase_vertical_summary,\n'
'        normalized_target_right_foot_y,\n'
'        source_reference_direction_global,\n'
'        target_local_rest_origin,\n'
'        normalized_target_local_rest_origin,\n'
'        animation.length,\n'
'    )\n')

def test_injects_full_direction_and_candidate_trajectory():
    out=probe.transform(BASE)
    assert probe.MARKER in out
    assert 'normalized_target_right_foot_positions' in out
    assert 'normalized_target_hips_relative_samples' in out
    assert 'normalized_target_left_local_rest_origin := target_left_local_rest_origin' in out

def test_rejects_double_patch_and_anchor_drift():
    out=probe.transform(BASE)
    with pytest.raises(ValueError): probe.transform(out)
    for anchor in ['left_foot_reference_ab','model_space_samples','normalized_target_right_foot_y.append']:
        with pytest.raises(ValueError): probe.transform(BASE.replace(anchor,anchor+'_drift',1))
