extends SceneTree

const MATERIAL_PATH := "res://game/scripts/brussels_osm_road_surface_material.gd"
const EXPECTED_FAMILY := "brussels_osm_road_surface_v1"
const EXPECTED_REVISION := 2

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_ROAD_MICROTEXTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var material_script := load(MATERIAL_PATH)
    if material_script == null:
        _fail("shared road material missing")
        return
    if not "PRESENTATION_REVISION" in material_script or int(material_script.PRESENTATION_REVISION) != EXPECTED_REVISION:
        _fail("road presentation revision 2 missing")
        return
    if str(material_script.MATERIAL_FAMILY) != EXPECTED_FAMILY:
        _fail("shared road material family changed")
        return

    var materials := material_script.create_materials() as Dictionary
    if materials.size() != 2:
        _fail("shared road family must remain exactly two role materials")
        return
    for role: String in ["regular", "major"]:
        var material := materials.get(role) as ShaderMaterial
        if material == null or material.shader == null:
            _fail("shared road shader material did not build for role: %s" % role)
            return
        if str(material.get_meta("license", "")) != "ODbL-1.0":
            _fail("OSM provenance/license metadata missing")
            return
        if bool(material.get_meta("surface_composition_claimed", true)):
            _fail("authored microtexture must not claim real road composition")
            return
        if bool(material.get_meta("aggregate_scale_claimed", true)):
            _fail("authored microtexture must not claim aggregate dimensions")
            return
        if bool(material.get_meta("wear_pattern_claimed", true)):
            _fail("authored microtexture must not claim real wear")
            return
        if bool(material.get_meta("crack_pattern_claimed", true)):
            _fail("authored microtexture must not claim crack semantics")
            return
        if bool(material.get_meta("road_marking_claimed", true)):
            _fail("shared material must not manufacture road markings")
            return
        if bool(material.get_meta("geometry_changed", true)):
            _fail("material presentation must not change road geometry")
            return
        if not bool(material.get_meta("authored_nonsemantic_microtexture", false)):
            _fail("non-semantic road microtexture metadata missing")
            return
        if bool(material.get_meta("microtexture_scale_source_measured", true)):
            _fail("road microtexture scale must remain explicitly non-measured")
            return
        var shader_code := material.shader.code
        for token: String in ["micro_grain_strength", "micro_grain_frequency", "fine_grain"]:
            if token not in shader_code:
                _fail("road microtexture shader contract missing token: %s" % token)
                return
        for forbidden: String in ["aggregate_size_m", "crack_width_m", "wear_lane_width_m", "lane_marking", "pothole"]:
            if forbidden in shader_code:
                _fail("unsupported authored road semantics leaked into shader: %s" % forbidden)
                return

    print("BRUSSELS_ROAD_MICROTEXTURE_OK: family=%s revision=%d roles=2 source=OSM authored-presentation license=ODbL-1.0 geometry_changed=false composition_claimed=false" % [EXPECTED_FAMILY, EXPECTED_REVISION])
    quit(0)
