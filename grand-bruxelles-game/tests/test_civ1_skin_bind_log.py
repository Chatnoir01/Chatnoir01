from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSESSOR = ROOT / "grand-bruxelles-game/tools/assess_civ1_skin_bind_log.py"


def _load():
    spec = spec_from_file_location("civ1_skin_bind", ASSESSOR)
    assert spec and spec.loader
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    module = _load()

    red_log = """ERROR: Skin bind #0 contains named bind 'mixamorig_Hips' but Skeleton3D has no bone by that name.\nERROR: Skin bind #46 contains named bind 'mixamorig_LeftFoot' but Skeleton3D has no bone by that name.\nCIV1_GLOBAL_CHAIN_DIAGNOSTIC_OK\n"""
    blocked = module.assess(red_log)
    assert blocked["skin_bind_integrity_verified"] is False
    assert blocked["skin_bind_error_count"] == 2
    assert blocked["missing_bone_names"] == ["mixamorig_Hips", "mixamorig_LeftFoot"]
    assert blocked["runtime_authorized"] is False
    assert blocked["visual_approval_claimed"] is False

    green_log = "CIV1_GLOBAL_CHAIN_DIAGNOSTIC_OK\n"
    clean = module.assess(green_log)
    assert clean["skin_bind_integrity_verified"] is True
    assert clean["skin_bind_error_count"] == 0
    assert clean["missing_bone_names"] == []

    print("CIV1_SKIN_BIND_LOG_TEST_OK")


if __name__ == "__main__":
    main()
