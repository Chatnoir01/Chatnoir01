import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "game" / "scripts" / "grand_place_owner_identity_presentation.gd"
MODULE = ROOT / "data" / "runtime" / "modules" / "grand_place_owner_identity_presentation.json"
CONTOUR = ROOT / "game" / "scripts" / "grand_place_complete_contour_runtime.gd"

EXPECTED_OWNER_IDS = ["1608847", "1608851", "1639974", "1635485", "1646728", "1654360"]


def test_identity_module_points_to_real_script_and_is_enabled():
    module = json.loads(MODULE.read_text(encoding="utf-8"))
    assert module == {"schema":"grand-bruxelles-runtime-module-v1","name":"GrandPlaceOwnerIdentityPresentation","path":"res://game/scripts/grand_place_owner_identity_presentation.gd","enabled":True}
    assert SCRIPT.is_file()


def test_identity_layer_is_bound_to_exact_urbis_owners_only():
    script = SCRIPT.read_text(encoding="utf-8")
    contour = CONTOUR.read_text(encoding="utf-8")
    for owner_id in EXPECTED_OWNER_IDS:
        assert f'"{owner_id}"' in script
        assert f'"{owner_id}"' in contour
    assert 'GrandPlaceContour_%s_WALLSURFACE' in script
    assert 'GrandPlaceContour_%s_ROOFSURFACE' in script
    assert 'get_loaded_owner_ids' in script


def test_cornet_renard_focus_contrast_has_fail_closed_runtime_guard():
    script = SCRIPT.read_text(encoding="utf-8")
    assert 'FOCUS_OWNER_IDS := ["1608847", "1608851"]' in script
    assert 'MIN_FOCUS_WALL_RGB_DELTA := 0.14' in script
    assert 'MIN_FOCUS_ROOF_RGB_DELTA := 0.09' in script
    assert '_focus_contrast_is_valid(owner_id, facts)' in script
    assert 'focus owner presentation contrast regressed' in script
    assert 'focus_contrast_guarded", true' in script


def test_focus_visibility_boost_is_material_only_and_bounded():
    script = SCRIPT.read_text(encoding="utf-8")
    assert 'FOCUS_EMISSION_ENERGY_MULTIPLIER := 0.18' in script
    assert 'mat.emission_enabled = true' in script
    assert 'mat.emission = base_color' in script
    assert 'mat.emission_energy_multiplier = FOCUS_EMISSION_ENERGY_MULTIPLIER' in script
    assert 'owner_id in FOCUS_OWNER_IDS' in script
    assert 'focus_visibility_guarded", true' in script
    assert 'mat.transparency' not in script
    assert 'mat.no_depth_test' not in script


def test_maison_du_roi_winding_diagnostic_is_exact_owner_tri_state_and_production_defaults_cull_back():
    script = SCRIPT.read_text(encoding="utf-8")
    required = [
        'WINDING_DIAGNOSTIC_OWNER_IDS := ["1654360"]',
        'mat.cull_mode = BaseMaterial3D.CULL_BACK',
        'func set_source_winding_diagnostic_cull_mode(mode: int) -> bool:',
        'source winding diagnostic cull mode requested before presentation readiness',
        'mode not in [BaseMaterial3D.CULL_BACK, BaseMaterial3D.CULL_FRONT, BaseMaterial3D.CULL_DISABLED]',
        'source winding diagnostic material ownership drifted',
        'GrandPlaceContour_%s_%s',
        'mat.cull_mode = mode',
        'source_winding_mitigation_enabled", false',
        'source_winding_mitigation_production_authorized", false',
        'source_winding_diagnostic_candidate',
        'return set_source_winding_diagnostic_cull_mode(BaseMaterial3D.CULL_DISABLED if enabled else BaseMaterial3D.CULL_BACK)',
    ]
    for marker in required:
        assert marker in script, f"winding diagnostic contract missing: {marker!r}"
    assert 'WINDING_DIAGNOSTIC_OWNER_IDS := ["1654360",' not in script


def test_presentation_cannot_mutate_geometry_or_collision_contract():
    script = SCRIPT.read_text(encoding="utf-8")
    assert 'source_geometry_changed", false' in script
    assert 'source_collision_changed", false' in script
    assert 'collision_object_count() -> int:\n    return 0' in script
    assert '.position =' not in script
    assert '.global_position =' not in script
    assert '.scale =' not in script
    assert 'create_trimesh_collision' not in script
    assert 'CollisionShape3D.new' not in script
    assert 'vertex' not in script.lower()


def test_colors_are_explicitly_presentation_only_not_photometric_claims():
    script = SCRIPT.read_text(encoding="utf-8")
    assert 'presentation_only", true' in script
    assert 'exact_rgb_is_photometric_measurement", false' in script
    assert 'presentation_dimensions_surveyed", false' in script
    assert 'finished_perfect", false' in script
