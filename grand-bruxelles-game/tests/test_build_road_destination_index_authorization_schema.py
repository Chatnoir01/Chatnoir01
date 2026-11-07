import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/city_machine/build_road_destination_index.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("build_road_destination_index", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _downstream():
    return {
        "source_registration_authorized": False,
        "road_cell_mapping_authorized": False,
        "render_authorized": False,
        "collision_authorized": False,
        "runtime_mount_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_authorized": False,
    }


def test_exact_downstream_authorization_schema_accepts_only_canonical_keys():
    module = _load_module()
    value = _downstream()
    assert module._require_exact_authorization(
        value, module.DOWNSTREAM_KEY_SET, "locked authorization"
    ) is value


@pytest.mark.parametrize("unexpected", ["registered", "runtime_override", "jouable_override"])
def test_downstream_authorization_schema_rejects_undeclared_keys(unexpected):
    module = _load_module()
    value = _downstream()
    value[unexpected] = False
    with pytest.raises(ValueError, match="schema mismatch"):
        module._require_exact_authorization(
            value, module.DOWNSTREAM_KEY_SET, "locked authorization"
        )


def test_downstream_authorization_schema_rejects_missing_key():
    module = _load_module()
    value = _downstream()
    del value["safe_spawn_authorized"]
    with pytest.raises(ValueError, match="schema mismatch"):
        module._require_exact_authorization(
            value, module.DOWNSTREAM_KEY_SET, "locked authorization"
        )


def test_manifest_authorization_schema_requires_source_acquisition_and_only_downstream_keys():
    module = _load_module()
    value = {"source_acquisition_authorized": True, **_downstream()}
    assert module._require_exact_authorization(
        value, module.MANIFEST_AUTHORIZATION_KEY_SET, "manifest authorization"
    ) is value

    value["render_anyway"] = False
    with pytest.raises(ValueError, match="schema mismatch"):
        module._require_exact_authorization(
            value, module.MANIFEST_AUTHORIZATION_KEY_SET, "manifest authorization"
        )
