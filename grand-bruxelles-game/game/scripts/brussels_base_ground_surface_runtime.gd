extends Node

const MATERIAL_FAMILY := "brussels_base_ground_surface_v1"
const PRESENTATION_REVISION := 6
const TARGET_MAIN_NODE := "Main"
const TARGET_GROUND_NODE := "Ground"
const REQUIRED_MAIN_ANCHORS := ["BrusselsOSM", "UrbISMidiExact", "Player"]
const EXPECTED_POSITION := Vector3(0.0, -0.23, 0.0)
const EXPECTED_SIZE := Vector3(1800.0, 0.4, 1800.0)
const GEOMETRY_TOLERANCE := 0.0001

var _main: Node = null
var _ground: CSGBox3D = null
var _legacy_material: Material = null
var _enhanced_material: ShaderMaterial = null
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _awaiting_main := false
var _bind_in_progress := false
var _tearing_down := false

func _ready() -> void:
    _tearing_down = false
    _awaiting_main = true
    _start_watching()
    call_deferred("_bind_existing_main")

func _exit_tree() -> void:
    _tearing_down = true
    _awaiting_main = false
    _bind_in_progress = false
    _stop_watching()
    _release_material_ownership()

func _start_watching() -> void:
    if _tearing_down or not is_inside_tree():
        return
    var tree := get_tree()
    if tree == null:
        return
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)
    if not tree.node_removed.is_connected(_on_node_removed):
        tree.node_removed.connect(_on_node_removed)

func _stop_watching() -> void:
    var tree := get_tree()
    if tree == null:
        return
    if tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)
    if tree.node_removed.is_connected(_on_node_removed):
        tree.node_removed.disconnect(_on_node_removed)

func _release_material_ownership() -> void:
    if _ground != null and is_instance_valid(_ground):
        if _ground.material == _enhanced_material:
            _ground.material = _legacy_material
    _main = null
    _ground = null
    _legacy_material = null
    _enhanced_material = null

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

func _is_production_main_candidate(main: Node) -> bool:
    if main == null or main.name != TARGET_MAIN_NODE:
        return false
    if main.get_node_or_null(TARGET_GROUND_NODE) == null:
        return false
    for anchor_name: String in REQUIRED_MAIN_ANCHORS:
        if main.get_node_or_null(anchor_name) == null:
            return false
    return true

func _is_authoritative_main(main: Node) -> bool:
    if main == null or not is_inside_tree():
        return false
    var tree := get_tree()
    if tree == null:
        return false
    if tree.current_scene == main:
        return true
    var parent := main.get_parent()
    if parent == tree.root:
        return true
    return str(main.name) == TARGET_MAIN_NODE and parent is Viewport and parent.get_parent() == tree.root

func _ground_contract_error(main: Node) -> String:
    var ground_candidate := main.get_node_or_null(TARGET_GROUND_NODE)
    if ground_candidate == null or not ground_candidate is CSGBox3D:
        return "production Ground missing or wrong type"
    var ground := ground_candidate as CSGBox3D
    if not _vectors_match(ground.position, EXPECTED_POSITION):
        return "Ground position drifted; refusing presentation mutation"
    if not _vectors_match(ground.size, EXPECTED_SIZE):
        return "Ground size drifted; refusing presentation mutation"
    if not ground.use_collision:
        return "Ground collision contract drifted"
    return ""

func _find_main_ancestor(node: Node) -> Node:
    var cursor: Node = node
    while cursor != null:
        if cursor.name == TARGET_MAIN_NODE:
            return cursor
        cursor = cursor.get_parent()
    return null

func _bind_existing_main() -> void:
    if _tearing_down or not is_inside_tree() or _ready_complete or _failed or _bind_in_progress:
        return
    var tree := get_tree()
    if tree == null:
        return
    var root_main := tree.root.get_node_or_null(TARGET_MAIN_NODE)
    if root_main != null and _is_production_main_candidate(root_main):
        _try_bind_main(root_main)
        return
    for candidate: Node in tree.root.find_children(TARGET_MAIN_NODE, "", true, false):
        if not _is_production_main_candidate(candidate):
            continue
        if not _is_authoritative_main(candidate):
            continue
        _try_bind_main(candidate)
        return

func _on_node_added(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _ready_complete or _failed or _bind_in_progress:
        return
    if node.name != TARGET_MAIN_NODE and node.name != TARGET_GROUND_NODE and not REQUIRED_MAIN_ANCHORS.has(str(node.name)):
        return
    var main := node if node.name == TARGET_MAIN_NODE else _find_main_ancestor(node)
    if main == null or not _is_production_main_candidate(main) or not _is_authoritative_main(main):
        return
    call_deferred("_try_bind_main", main)

func _on_node_removed(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or not _ready_complete:
        return
    if node != _ground and node != _main:
        return
    _release_material_ownership()
    _ready_complete = false
    _failed = false
    _awaiting_main = true
    _bind_in_progress = false
    _start_watching()
    call_deferred("_bind_existing_main")

func _try_bind_main(main: Node) -> void:
    if _tearing_down or not is_inside_tree() or _ready_complete or _failed or _bind_in_progress:
        return
    if not _is_production_main_candidate(main) or not _is_authoritative_main(main):
        return
    _bind_in_progress = true
    var contract_error := _ground_contract_error(main)
    if not contract_error.is_empty():
        _fail_binding(contract_error)
        return

    _main = main
    _ground = main.get_node_or_null(TARGET_GROUND_NODE) as CSGBox3D
    _legacy_material = _ground.material
    _enhanced_material = _make_material()
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    _finish_waiting()
    print("BRUSSELS_BASE_GROUND_SURFACE_READY: family=%s revision=%d material_only=true geometry_changed=false collision_changed=false procedural=true time_dependent=false camera_dependent=false multidirectional=true event_driven=true production_anchors=true authority_topology=true" % [MATERIAL_FAMILY, PRESENTATION_REVISION])

func _fail_binding(message: String) -> void:
    if _tearing_down:
        return
    push_error("Brussels base-ground surface runtime: %s" % message)
    _failed = true
    _ready_complete = true
    _finish_waiting()

func _finish_waiting() -> void:
    _awaiting_main = false
    _bind_in_progress = false

func _set_material_state(enabled: bool) -> void:
    if _tearing_down or not is_inside_tree():
        return
    if _ground == null or not is_instance_valid(_ground):
        return
    var current := _ground.material
    if enabled:
        if current == _legacy_material or current == _enhanced_material:
            _ground.material = _enhanced_material
        return
    if current == _enhanced_material or current == _legacy_material:
        _ground.material = _legacy_material

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if _ready_complete and not _failed and not _tearing_down and is_inside_tree():
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
