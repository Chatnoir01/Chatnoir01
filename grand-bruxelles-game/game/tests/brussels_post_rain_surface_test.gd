extends SceneTree

const HELPER := "res://game/scripts/brussels_post_rain_surface_material.gd"
const MIDI_SCRIPT := "res://game/scripts/urbis_midi_builder.gd"
const BOURSE_SCRIPT := "res://game/scripts/urbis_bourse_surface_context.gd"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if not ResourceLoader.exists(HELPER):
        _fail("shared post-rain helper missing")
        return
    var helper_script := load(HELPER)
    if helper_script == null:
        _fail("shared post-rain helper did not load")
        return
    var material: Material = helper_script.make(Color(0.42, 0.40, 0.37, 1.0), 0.94, 0.62)
    if material == null or not material is ShaderMaterial:
        _fail("shared helper must return ShaderMaterial")
        return
    if not bool(material.get_meta("brussels_post_rain", false)):
        _fail("post-rain provenance metadata missing")
        return
    if absf(float(material.get_meta("wetness_strength", -1.0)) - 0.62) > 0.001:
        _fail("wetness metadata mismatch")
        return
    var shader := (material as ShaderMaterial).shader
    if shader == null:
        _fail("wet material shader missing")
        return
    var code := shader.code
    for token: String in ["ROUGHNESS", "SPECULAR", "world_xz", "wetness"]:
        if token not in code:
            _fail("wet shader contract missing token: %s" % token)
            return

    for script_path: String in [MIDI_SCRIPT, BOURSE_SCRIPT]:
        var text := FileAccess.get_file_as_string(script_path)
        if "post_rain_wetness" not in text:
            _fail("runtime integration missing wetness control in %s" % script_path)
            return
        if "brussels_post_rain_surface_material.gd" not in text:
            _fail("runtime integration missing shared helper in %s" % script_path)
            return

    print("Brussels post-rain shared surface regression: PASS")
    quit(0)

func _fail(message: String) -> void:
    push_error("BRUSSELS_POST_RAIN_SURFACE_FAIL: " + message)
    quit(1)
