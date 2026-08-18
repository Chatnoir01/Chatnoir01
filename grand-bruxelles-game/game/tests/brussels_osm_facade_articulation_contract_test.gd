extends SceneTree

const MATERIAL_PATH := "res://game/scripts/brussels_osm_facade_articulation_material.gd"
const RUNTIME_PATH := "res://game/scripts/brussels_osm_facade_articulation_runtime.gd"
const FAMILY := "brussels_osm_facade_articulation_v1"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_FACADE_ARTICULATION_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    if not FileAccess.file_exists(MATERIAL_PATH):
        _fail("reusable facade articulation material missing")
        return
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("facade articulation runtime missing")
        return
    var material_script: Script = load(MATERIAL_PATH)
    if material_script == null:
        _fail("material script does not load")
        return
    var material: Variant = material_script.call("create_material", Color(0.46, 0.40, 0.34, 1.0), 0.91)
    if not material is ShaderMaterial:
        _fail("factory did not return ShaderMaterial")
        return
    if str((material as ShaderMaterial).get_meta("material_family", "")) != FAMILY:
        _fail("unexpected material family")
        return
    if bool((material as ShaderMaterial).get_meta("geometry_changed", true)):
        _fail("material claims geometry change")
        return
    if bool((material as ShaderMaterial).get_meta("window_geometry_claimed", true)):
        _fail("material must not claim window geometry")
        return
    if bool((material as ShaderMaterial).get_meta("building_material_claimed", true)):
        _fail("material must not claim source building material")
        return
    if str((material as ShaderMaterial).get_meta("license", "")) != "ODbL-1.0":
        _fail("OSM licence metadata missing")
        return
    print("BRUSSELS_OSM_FACADE_ARTICULATION_OK: family=%s geometry_changed=false source_material_claimed=false" % FAMILY)
    quit(0)
