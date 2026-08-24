extends SceneTree

const RUNTIME_PATH := "res://game/scripts/brussels_base_ground_surface_runtime.gd"
const EXPECTED_FAMILY := "brussels_base_ground_surface_v1"
const EXPECTED_REVISION := 8
const EXPECTED_CALIBRATION := 2
const EXPECTED_PROFILE := "authored_near_field_isotropic_variation_v8"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_SURFACE_CONTRACT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var script: Script = load(RUNTIME_PATH) as Script
    if script == null:
        _fail("runtime missing")
        return
    if int(script.PRESENTATION_REVISION) != EXPECTED_REVISION or int(script.CALIBRATION_REVISION) != EXPECTED_CALIBRATION:
        _fail("presentation/calibration revision mismatch")
        return
    if str(script.VISUAL_RECIPE_PROFILE) != EXPECTED_PROFILE or str(script.MATERIAL_FAMILY) != EXPECTED_FAMILY:
        _fail("family/profile mismatch")
        return
    var runtime: Node = script.new() as Node
    if runtime == null:
        _fail("runtime could not be instantiated")
        return
    var material: Variant = runtime.call("_make_material")
    if not material is ShaderMaterial:
        _fail("runtime did not produce ShaderMaterial")
        return
    var mat: ShaderMaterial = material as ShaderMaterial
    if mat.shader == null:
        _fail("shader missing")
        return
    var code: String = mat.shader.code
    for token: String in ["p_a", "p_b", "p_c", "broad_a", "broad_b", "broad_c", "fine_a", "fine_b", "fine_c", "distance_visibility", "float distance_contrast = distance_visibility", "smoothstep(34.0, 102.0", "mix(broad, fine, detail_weight)"]:
        if not code.contains(token):
            _fail("required v8 token missing: %s" % token)
            return
    for forbidden: String in ["TIME", "mix(0.12, 1.0, distance_visibility)", "value_noise(world_pos.xz"]:
        if code.contains(forbidden):
            _fail("forbidden anti-banding regression present: %s" % forbidden)
            return
    if int(mat.get_meta("anti_banding_revision", 0)) != 2 or not bool(mat.get_meta("far_field_contrast_zero", false)):
        _fail("far-field anti-banding contract missing")
        return
    if not bool(mat.get_meta("distance_contrast_fade", false)):
        _fail("distance fade contract missing")
        return
    for unsupported: String in ["surface_composition_claimed", "surface_identity_claimed", "microtexture_scale_source_measured", "exact_rgb_is_photometric_measurement"]:
        if bool(mat.get_meta(unsupported, true)):
            _fail("unsupported source claim enabled: %s" % unsupported)
            return
    if bool(mat.get_meta("geometry_changed", true)) or bool(mat.get_meta("collision_changed", true)):
        _fail("material contract mutated geometry/collision")
        return
    print("BRUSSELS_BASE_GROUND_SURFACE_CONTRACT_OK: family=%s revision=%d calibration=%d profile=%s far_field_contrast_zero=true anti_banding=2" % [EXPECTED_FAMILY, EXPECTED_REVISION, EXPECTED_CALIBRATION, EXPECTED_PROFILE])
    quit(0)
