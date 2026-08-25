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
