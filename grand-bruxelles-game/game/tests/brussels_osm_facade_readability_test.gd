extends SceneTree

const MATERIAL_PATH := "res://game/scripts/brussels_osm_facade_surface_material.gd"
const EXPECTED_FAMILY := "brussels_osm_facade_surface_v1"
const EXPECTED_PRESENTATION_REVISION := 2

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_FACADE_READABILITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var material_script := load(MATERIAL_PATH)
    if material_script == null:
        _fail("generic facade material script missing")
        return
    if not "PRESENTATION_REVISION" in material_script:
        _fail("generic facade presentation revision 2 missing")
        return
    if int(material_script.PRESENTATION_REVISION) != EXPECTED_PRESENTATION_REVISION:
        _fail("generic facade presentation revision mismatch")
        return

    var material := material_script.create_material(Color(0.47, 0.43, 0.38, 1.0), 0.90) as ShaderMaterial
    if material == null or material.shader == null:
        _fail("generic facade material creation failed")
        return
    if str(material.get_meta("material_family", "")) != EXPECTED_FAMILY:
        _fail("generic facade material family changed")
        return
    if str(material.get_meta("license", "")) != "ODbL-1.0":
        _fail("generic facade provenance license changed")
        return
    if bool(material.get_meta("geometry_changed", true)):
        _fail("generic facade readability revision changed geometry")
        return

    for unsupported: String in [
        "building_material_claimed",
        "brick_claimed",
        "stone_claimed",
        "concrete_claimed",
        "weathering_claimed",
        "facade_unit_scale_claimed",
        "architectural_detail_claimed",
        "surface_composition_claimed",
        "microtexture_scale_source_measured"
    ]:
        if bool(material.get_meta(unsupported, true)):
            _fail("unsupported generic facade claim enabled: %s" % unsupported)
            return

    var shader_code := material.shader.code
    for required_token: String in ["surface_readability_strength", "fine_grain", "readability"]:
        if shader_code.find(required_token) < 0:
            _fail("generic facade readability shader contract missing: %s" % required_token)
            return
    for forbidden_token: String in ["mortar", "brick_course", "window_grid", "floor_band", "stone_joint"]:
        if shader_code.find(forbidden_token) >= 0:
            _fail("generic facade shader manufactured architectural semantics: %s" % forbidden_token)
            return

    var strength: Variant = material.get_shader_parameter("surface_readability_strength")
    if not strength is float or float(strength) <= 0.0 or float(strength) > 0.30:
        _fail("generic facade readability strength is missing or unbounded")
        return

    print("BRUSSELS_OSM_FACADE_READABILITY_OK: family=%s revision=%d strength=%.3f source=OSM license=ODbL-1.0 geometry_changed=false" % [EXPECTED_FAMILY, EXPECTED_PRESENTATION_REVISION, float(strength)])
    quit(0)
