extends SceneTree

const BUILDER := preload("res://game/scripts/urbis_hero_builder.gd")
const STYLE_PATH := "res://data/qa/bourse_runtime_material_style.json"
const GEOMETRY_PATH := "res://data/urbis/heroes/bourse_lod2.game.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_RUNTIME_MATERIAL_STYLE_FAIL: %s" % message)
    quit(1)

func _rgba(raw: Variant) -> Color:
    if not raw is Array or raw.size() != 4:
        return Color(-1, -1, -1, -1)
    return Color(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))

func _run() -> void:
    var style_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(STYLE_PATH))
    if typeof(style_raw) != TYPE_DICTIONARY:
        _fail("style contract missing or invalid")
        return
    var style := style_raw as Dictionary
    if str(style.get("schema", "")) != "grand-bruxelles-hero-material-style-v1":
        _fail("style schema drifted")
        return
    if bool(style.get("geometry_mutation_allowed", true)):
        _fail("style contract may not mutate geometry")
        return
    if not bool(style.get("runtime_visual_approved", false)):
        _fail("style contract must be visual-runtime approved")
        return

    var geometry_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY_PATH))
    if typeof(geometry_raw) != TYPE_DICTIONARY:
        _fail("authoritative Bourse geometry missing")
        return
    var geometry := geometry_raw as Dictionary
    var expected_triangles := 0
    for raw_face: Variant in geometry.get("faces", []):
        if raw_face is Dictionary:
            expected_triangles += (raw_face as Dictionary).get("triangles", []).size()

    var builder := BUILDER.new()
    builder.name = "BourseMaterialStyleBuilderTest"
    builder.build_collisions = false
    root.add_child(builder)
    await process_frame
    await process_frame

    var hero := builder.get_node_or_null("Hero_Bourse")
    if hero == null:
        _fail("Bourse hero was not built")
        return
    if not bool(hero.get_meta("runtime_material_style_applied", false)):
        _fail("runtime material style was not applied")
        return
    if str(hero.get_meta("geometry_path", "")) != GEOMETRY_PATH:
        _fail("geometry path changed while applying material style")
        return
    if int(hero.get_meta("triangle_count", -1)) != expected_triangles:
        _fail("triangle count changed while applying material style")
        return

    var walls := hero.get_node_or_null("Walls") as MeshInstance3D
    if walls == null or walls.mesh == null or walls.mesh.get_surface_count() < 1:
        _fail("Bourse wall surface missing")
        return
    var material := walls.mesh.surface_get_material(0) as StandardMaterial3D
    if material == null:
        _fail("Bourse wall material missing")
        return
    var expected_wall := _rgba((style.get("materials", {}) as Dictionary).get("wall", {}).get("albedo_rgba", []))
    if not material.albedo_color.is_equal_approx(expected_wall):
        _fail("wall albedo does not match style contract")
        return
    if absf(material.roughness - 0.91) > 0.0001:
        _fail("wall roughness does not match style contract")
        return

    print("BOURSE_RUNTIME_MATERIAL_STYLE_OK: triangles=%d wall=%s roughness=%.2f geometry_unchanged=true" % [expected_triangles, str(material.albedo_color), material.roughness])
    builder.queue_free()
    quit(0)
