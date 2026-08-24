extends Node

const MATERIAL_FAMILY := "brussels_base_ground_surface_v1"
const PRESENTATION_REVISION := 7
const VISUAL_RECIPE_PROFILE := "authored_isotropic_neutral_variation_v7"
const CALIBRATION_REVISION := 1
const TARGET_MAIN_NODE := "Main"
const TARGET_GROUND_NODE := "Ground"
const EXPECTED_POSITION := Vector3(0.0, -0.23, 0.0)
const EXPECTED_SIZE := Vector3(1800.0, 0.4, 1800.0)
const GEOMETRY_TOLERANCE := 0.0001

var _ground: CSGBox3D = null
var _legacy_material: Material = null
var _enhanced_material: ShaderMaterial = null
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _make_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 ground_dark_color = vec4(0.155, 0.160, 0.157, 1.0);
uniform vec4 ground_light_color = vec4(0.265, 0.258, 0.242, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.93;
uniform float tone_contrast_gain : hint_range(1.0, 2.0) = 1.45;

varying vec3 world_pos;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    vec2 smooth_local = local * local * (3.0 - 2.0 * local);
    float a = hash21(cell);
    float b = hash21(cell + vec2(1.0, 0.0));
    float c = hash21(cell + vec2(0.0, 1.0));
    float d = hash21(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, smooth_local.x), mix(c, d, smooth_local.x), smooth_local.y);
}

vec2 rotate2(vec2 p, float c, float s) {
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = world_pos.xz;
    vec2 p_a = rotate2(p, 0.819152, 0.573576);
    vec2 p_b = rotate2(p, 0.390731, -0.920505);
    vec2 p_c = rotate2(p, -0.707107, 0.707107);

    // Human review of calibration v7.1 found low-frequency world-space noise
    // perspective-compressed into horizontal streaks. Keep the authored recipe
    // isotropic but move macro variation into sub-meter/meter scales and fade
    // all presentation contrast with distance instead of letting compressed far
    // field bands dominate the player frame.
    float broad_a = value_noise(p_a * 0.62 + vec2(19.0, 37.0));
    float broad_b = value_noise(p_b * 0.83 + vec2(71.0, 11.0));
    float broad_c = value_noise(p_c * 1.07 + vec2(43.0, 67.0));
    float broad = (broad_a + broad_b + broad_c) / 3.0;

    float fine_a = value_noise(p_a * 1.95 + vec2(31.0, 83.0));
    float fine_b = value_noise(p_b * 2.55 + vec2(97.0, 53.0));
    float fine_c = value_noise(p_c * 3.15 + vec2(59.0, 29.0));
    float fine = (fine_a + fine_b + fine_c) / 3.0;

    float camera_distance = distance(world_pos, CAMERA_POSITION_WORLD);
    float near_detail = 1.0 - smoothstep(18.0, 72.0, camera_distance);
    float distance_visibility = 1.0 - smoothstep(55.0, 145.0, camera_distance);
    float detail_weight = mix(0.28, 0.58, near_detail);
    float raw_ground_tone = mix(broad, fine, detail_weight);
    float centered_ground_tone = raw_ground_tone - 0.5;
    float distance_contrast = mix(0.12, 1.0, distance_visibility);
    float authored_ground_tone = clamp(0.5 + centered_ground_tone * tone_contrast_gain * distance_contrast, 0.0, 1.0);

    ALBEDO = mix(ground_dark_color.rgb, ground_light_color.rgb, authored_ground_tone);
    ROUGHNESS = clamp(base_roughness + (0.5 - fine) * 0.020 * near_detail, 0.90, 0.96);
    METALLIC = 0.0;
    SPECULAR = 0.08;
}
"""

    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("presentation_revision", PRESENTATION_REVISION)
    material.set_meta("visual_recipe_profile", VISUAL_RECIPE_PROFILE)
    material.set_meta("calibration_revision", CALIBRATION_REVISION)
    material.set_meta("anti_banding_revision", 1)
    material.set_meta("distance_contrast_fade", true)
    material.set_meta("procedural_only", true)
    material.set_meta("time_dependent", false)
    material.set_meta("geometry_changed", false)
    material.set_meta("collision_changed", false)
    material.set_meta("surface_composition_claimed", false)
    material.set_meta("surface_identity_claimed", false)
    material.set_meta("microtexture_scale_source_measured", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material

func _vectors_match(a: Vector3, b: Vector3) -> bool:
    return a.distance_to(b) <= GEOMETRY_TOLERANCE

func _apply_when_ready() -> void:
    var main: Node = null
    for _attempt: int in range(180):
        await get_tree().process_frame
        var candidate := get_tree().root.get_node_or_null(TARGET_MAIN_NODE)
        if candidate != null:
            main = candidate
            break
    if main == null:
        push_error("Brussels base-ground surface runtime: production Main missing")
        _failed = true
        _ready_complete = true
        return

    var ground_candidate := main.get_node_or_null(TARGET_GROUND_NODE)
    if not ground_candidate is CSGBox3D:
        push_error("Brussels base-ground surface runtime: production Ground missing or wrong type")
        _failed = true
        _ready_complete = true
        return

    _ground = ground_candidate as CSGBox3D
    if not _vectors_match(_ground.position, EXPECTED_POSITION):
        push_error("Brussels base-ground surface runtime: Ground position drifted; refusing presentation mutation")
        _failed = true
        _ready_complete = true
        return
    if not _vectors_match(_ground.size, EXPECTED_SIZE):
        push_error("Brussels base-ground surface runtime: Ground size drifted; refusing presentation mutation")
        _failed = true
        _ready_complete = true
        return
    if not _ground.use_collision:
        push_error("Brussels base-ground surface runtime: Ground collision contract drifted")
        _failed = true
        _ready_complete = true
        return

    _legacy_material = _ground.material
    _enhanced_material = _make_material()
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_BASE_GROUND_SURFACE_READY: family=%s revision=%d calibration=%d profile=%s anti_banding=1 material_only=true geometry_changed=false collision_changed=false procedural=true time_dependent=false" % [MATERIAL_FAMILY, PRESENTATION_REVISION, CALIBRATION_REVISION, VISUAL_RECIPE_PROFILE])

func _set_material_state(enabled: bool) -> void:
    if _ground == null or not is_instance_valid(_ground):
        return
    _ground.material = _enhanced_material if enabled else _legacy_material

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if _ready_complete and not _failed:
        _set_material_state(enabled)

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func material_family() -> String:
    return MATERIAL_FAMILY

func presentation_revision() -> int:
    return PRESENTATION_REVISION

func visual_recipe_profile() -> String:
    return VISUAL_RECIPE_PROFILE
