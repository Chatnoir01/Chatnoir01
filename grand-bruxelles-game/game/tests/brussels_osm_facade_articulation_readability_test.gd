extends SceneTree

const MATERIAL_PATH := "res://game/scripts/brussels_osm_facade_articulation_material.gd"
const EXPECTED_FAMILY := "brussels_osm_facade_articulation_v1"
const EXPECTED_LICENSE := "ODbL-1.0"
const EXPECTED_SOURCE_FRAGMENT := "OpenStreetMap contributors via Overpass API; generic building footprint/placement/kind only"
const EXPECTED_RECIPE_PROVENANCE := "authored_presentation_from_existing_mesh_normal_not_source_measurement"
const EXPECTED_READABILITY_PROFILE := "isotropic_contrast_shaped_fine_grain_v3"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_FACADE_ARTICULATION_READABILITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var factory := load(MATERIAL_PATH)
    if factory == null:
        _fail("active facade articulation material missing"); return
    if not "PRESENTATION_REVISION" in factory or int(factory.PRESENTATION_REVISION) != 2:
        _fail("active facade articulation presentation revision 2 missing"); return
    var material := factory.create_material(Color(0.45, 0.40, 0.34, 1.0), 0.91) as ShaderMaterial
    if material == null or str(material.get_meta("material_family", "")) != EXPECTED_FAMILY:
        _fail("active facade articulation family mismatch"); return
    if str(material.get_meta("license", "")) != EXPECTED_LICENSE:
        _fail("active facade articulation license mismatch"); return
    var source_label := str(material.get_meta("source_label", ""))
    if not source_label.begins_with(EXPECTED_SOURCE_FRAGMENT) or EXPECTED_LICENSE not in source_label:
        _fail("active facade articulation source scope/provenance mismatch"); return
    if str(material.get_meta("visual_recipe_provenance", "")) != EXPECTED_RECIPE_PROVENANCE:
        _fail("active facade articulation authored recipe provenance mismatch"); return
    if str(material.get_meta("readability_profile", "")) != EXPECTED_READABILITY_PROFILE:
        _fail("active facade articulation readability profile mismatch"); return
    var strength: Variant = material.get_shader_parameter("surface_readability_strength")
    if strength == null or float(strength) <= 0.0 or float(strength) > 0.25:
        _fail("bounded readability strength missing"); return
    if bool(material.get_meta("geometry_changed", true)):
        _fail("readability material may not change geometry"); return
    for forbidden: String in ["building_material_claimed", "window_geometry_claimed", "masonry_units_claimed", "weathering_claimed", "surface_composition_claimed", "mortar_pattern_claimed", "brick_course_claimed", "stone_joint_claimed", "microtexture_scale_source_measured", "exact_rgb_is_photometric_measurement", "normal_is_source_measurement"]:
        if bool(material.get_meta(forbidden, true)):
            _fail("unsupported semantic/source claim enabled: %s" % forbidden); return
    var code := material.shader.code
    for forbidden_token: String in ["mortar", "brick_course", "stone_joint", "window_grid", "floor_band"]:
        if forbidden_token in code:
            _fail("manufactured facade semantics leaked into shader: %s" % forbidden_token); return
    if not "fine_grain" in code or not "surface_readability_strength" in code or not "pow(" in code:
        _fail("contrast-shaped facade readability shader path missing"); return
    print("BRUSSELS_OSM_FACADE_ARTICULATION_READABILITY_OK: family=%s revision=2 strength=%.3f profile=%s source=OSM license=%s geometry_changed=false provenance_locked=true" % [EXPECTED_FAMILY, float(strength), EXPECTED_READABILITY_PROFILE, EXPECTED_LICENSE])
    quit(0)
