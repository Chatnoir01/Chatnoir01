import copy
import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / 'tools' / 'qa' / 'check_gate8_variant01_kaykit_walk_source_intake.py'
spec = importlib.util.spec_from_file_location('kaykit_intake_check', MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

def valid_contract():
    return {
        'license': 'CC0-1.0',
        'source_page': 'https://opengameart.org/content/kaykit-character-animations',
        'download_url': 'https://opengameart.org/sites/default/files/kaykit_character_animations_1.2.zip',
        'format_expectations': ['gltf', 'fbx'],
        'semantic_expectations': ['idle', 'walk', 'run'],
        'pin_state': 'PINNED_FIRST_PARTY_BYTES_VERIFIED',
        'source_sha256': module.EXPECTED_SHA256,
        'source_size_bytes': module.EXPECTED_SIZE,
        **module.EXPECTED_COUNTS,
        'pin_evidence_run': 32876921778,
        'pin_evidence_artifact': 9574284192,
        'mechanical_preflight_run': 32889773170,
        'mechanical_preflight_artifact': 9578990115,
        'mechanical_preflight_artifact_sha256': 'daf31a2cacd159ae5b9bf4207b40979fc33ce66a7cfdfbacd9aaaa51072447dd',
        'mechanical_preflight_state': module.BLOCK_STATE,
        'observed_skeleton_bone_count': 6,
        'observed_bone_names': module.EXPECTED_BONES,
        'missing_required_humanoid_roles': module.EXPECTED_MISSING_ROLES,
        'target_humanoid_retarget_compatible': False,
        'candidate_target_verdict': module.BLOCK_VERDICT,
        'walk_candidate_state': module.BLOCK_VERDICT,
        'run_candidate_state': module.BLOCK_VERDICT,
        'production_authorized': False,
        'activation_ready': False,
        'adoption_ready': False,
        'mixamo_allowed': False,
        'player_character_reuse_allowed': False,
        'walk_alias_selected': '',
        'run_alias_selected': '',
    }

def test_verified_contract_passes():
    assert module.validate(valid_contract()) == []

def test_sha_or_size_drift_fails():
    for key, bad_value in [('source_sha256', '0' * 64), ('source_size_bytes', module.EXPECTED_SIZE + 1)]:
        data = copy.deepcopy(valid_contract())
        data[key] = bad_value
        assert module.validate(data), key

def test_production_or_alias_opening_fails():
    data = copy.deepcopy(valid_contract())
    data['production_authorized'] = True
    assert module.validate(data)
    data = copy.deepcopy(valid_contract())
    data['walk_alias_selected'] = 'Walk'
    assert module.validate(data)

def test_archive_inventory_drift_fails():
    for key in module.EXPECTED_COUNTS:
        data = copy.deepcopy(valid_contract())
        data[key] += 1
        assert module.validate(data), key

def test_mechanical_block_evidence_drift_fails():
    cases = [
        ('mechanical_preflight_state', 'READY'),
        ('observed_skeleton_bone_count', 7),
        ('observed_bone_names', module.EXPECTED_BONES[:-1]),
        ('missing_required_humanoid_roles', module.EXPECTED_MISSING_ROLES[:-1]),
        ('target_humanoid_retarget_compatible', True),
        ('candidate_target_verdict', 'GARDER'),
    ]
    for key, value in cases:
        data = copy.deepcopy(valid_contract())
        data[key] = value
        assert module.validate(data), key
