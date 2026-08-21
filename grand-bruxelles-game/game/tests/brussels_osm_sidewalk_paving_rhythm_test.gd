extends SceneTree

const MATERIAL_PATH := "res://game/scripts/brussels_osm_sidewalk_surface_material.gd"
const EXPECTED_FAMILY := "brussels_osm_sidewalk_surface_v1"
const EXPECTED_REVISION := 2

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_SIDEWALK_MICROTEXTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var material_script := load(MATERIAL_PATH)
    if material_script == null:
        _fail("shared sidewalk material missing")
        return
    if not "PRESENTATION_REVISION" in material_script or int(material_script.PRESENTATION_REVISION) != EXPECTED_REVISION:
        _fail("sidewalk presentation revision 2 missing")
        return
    if str(material_script.MATERIAL_FAMILY) != EXPECTED_FAMILY:
        _fail("shared material family changed")
        return

    var material := material_script.create_material() as ShaderMaterial
    if material == null or material.shader == null:
        _fail("shared sidewalk shader material did not build")
        return
    if str(material.get_meta("license", "")) != "ODbL-1.0":
        _fail("OSM provenance/license metadata missing")
        return
    if bool(material.get_meta("surface_composition_claimed", true)):
        _fail("authored microtexture must not claim real composition")
        return
    if bool(material.get_meta("paving_unit_dimensions_claimed", true)):
        _fail("authored microtexture must not claim paving dimensions")
        return
    if bool(material.get_meta("geometry_changed", true)):
        _fail("material presentation must not change geometry")
        return
    if not bool(material.get_meta("authored_nonsemantic_microtexture", false)):
        _fail("non-semantic microtexture metadata missing")
        return
    if bool(material.get_meta("microtexture_scale_source_measured", true)):
        _fail("microtexture scale must remain explicitly non-measured")
        return

    var shader_code := material.shader.code
    for token: String in ["micro_grain_strength", "micro_grain_frequency", "fine_grain"]:
        if token not in shader_code:
            _fail("microtexture shader contract missing token: %s" % token)
            return
    for forbidden: String in ["joint_spacing_m", "joint_width_m", "paving_joint"]:
        if forbidden in shader_code:
            _fail("production-wall forbidden paving-joint dimension contract leaked into shader: %s" % forbidden)
            return

    print("BRUSSELS_SIDEWALK_MICROTEXTURE_OK: family=%s revision=%d source=OSM-adjacent authored-presentation license=ODbL-1.0 geometry_changed=false paving_dimensions_claimed=false" % [EXPECTED_FAMILY, EXPECTED_REVISION])
    quit(0)
