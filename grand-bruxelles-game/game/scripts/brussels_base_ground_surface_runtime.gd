extends Node

const MATERIAL_FAMILY := "brussels_base_ground_surface_v1"
const PRESENTATION_REVISION := 6
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
var _watching_tree := false

func _ready() -> void:
    _start_watching()
    call_deferred("_try_bind_existing_mount")

func _start_watching() -> void:
    if _watching_tree:
        return
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)
    _watching_tree = true

func _stop_watching() -> void:
    if not _watching_tree:
        return
    if get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.disconnect(_on_node_added)
    _watching_tree = false

func _on_node_added(node: Node) -> void:
    if _ready_complete or _failed:
        return
    if node.name == TARGET_MAIN_NODE or node.name == TARGET_GROUND_NODE:
        call_deferred("_try_bind_existing_mount")

func _is_production_main(candidate: Node) -> bool:
    if candidate == null or candidate.name != TARGET_MAIN_NODE:
        return false
    if candidate.get_node_or_null(TARGET_GROUND_NODE) == null:
        return false
    return candidate.get_node_or_null("BrusselsOSM") != null \
        and candidate.get_node_or_null("UrbISMidiExact") != null \
        and candidate.get_node_or_null("Player") != null

func _find_main_recursive(node: Node) -> Node:
    if _is_production_main(node):
        return node
    for child: Node in node.get_children():
        var found := _find_main_recursive(child)
        if found != null:
            return found
    return null

func _try_bind_existing_mount() -> void:
    if _ready_complete or _failed:
        return
    var main: Node = get_tree().current_scene
    if not _is_production_main(main):
        main = _find_main_recursive(get_tree().root)
    if main == null:
        return
    _bind_main(main)

func _make_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 ground_dark_color = vec4(0.135, 0.139, 0.137, 1.0);
uniform vec4 ground_light_color = vec4(0.180, 0.184, 0.180, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.95;

varying vec3 world_pos;

const mat2 ROT_A = mat2(vec2(0.798636, 0.601815), vec2(-0.601815, 0.798636));
const mat2 ROT_B = mat2(vec2(0.438371, -0.898794), vec2(0.898794, 0.438371));

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

float authored_isotropic_noise(vec2 p) {
    float n0 = value_noise(p * 0.028 + vec2(19.0, 37.0));
    float n1 = value_noise((ROT_A * p) * 0.041 + vec2(71.0, 11.0));
    float n2 = value_noise((ROT_B * p) * 0.056 + vec2(43.0, 83.0));
    float n3 = value_noise((ROT_A * ROT_B * p) * 0.073 + vec2(97.0, 29.0));
    return (n0 + n1 + n2 + n3) * 0.25;
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float macro_a = authored_isotropic_noise(world_pos.xz * 0.72);
    float macro_b = authored_isotropic_noise((ROT_B * world_pos.xz) * 0.31 + vec2(13.0, 57.0));
    float authored_ground_tone = clamp(
        0.5 + (macro_a - 0.5) * 0.34 + (macro_b - 0.5) * 0.12,
        0.34,
        0.66
    );
    ALBEDO = mix(ground_dark_color.rgb, ground_light_color.rgb, authored_ground_tone);
    ROUGHNESS = clamp(base_roughness + (macro_b - 0.5) * 0.008, 0.94, 0.96);
    METALLIC = 0.0;
    SPECULAR = 0.07;
}
"""

    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("presentation_revision", PRESENTATION_REVISION)
    material.set_meta("procedural_only", true)
    material.set_meta("time_dependent", false)
    material.set_meta("camera_dependent_recipe", false)
    material.set_meta("multidirectional_isotropic_recipe", true)
    material.set_meta("perspective_safe_macro_recipe", true)
    material.set_meta("geometry_changed", false)
    material.set_meta("collision_changed", false)
    material.set_meta("surface_composition_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material

func _vectors_match(a: Vector3, b: Vector3) -> bool:
    return a.distance_to(b) <= GEOMETRY_TOLERANCE

func _bind_main(main: Node) -> void:
    var ground_candidate := main.get_node_or_null(TARGET_GROUND_NODE)
    if not ground_candidate is CSGBox3D:
        _fail_closed("production Ground missing or wrong type")
        return

    _ground = ground_candidate as CSGBox3D
    if not _vectors_match(_ground.position, EXPECTED_POSITION):
        _fail_closed("Ground position drifted; refusing presentation mutation")
        return
    if not _vectors_match(_ground.size, EXPECTED_SIZE):
        _fail_closed("Ground size drifted; refusing presentation mutation")
        return
    if not _ground.use_collision:
        _fail_closed("Ground collision contract drifted")
        return

    _legacy_material = _ground.material
    _enhanced_material = _make_material()
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    _stop_watching()
    print("BRUSSELS_BASE_GROUND_SURFACE_READY: family=%s revision=%d material_only=true geometry_changed=false collision_changed=false procedural=true time_dependent=false camera_dependent=false multidirectional=true event_driven=true" % [MATERIAL_FAMILY, PRESENTATION_REVISION])

func _fail_closed(message: String) -> void:
    push_error("Brussels base-ground surface runtime: %s" % message)
    _failed = true
    _ready_complete = true
    _stop_watching()

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
