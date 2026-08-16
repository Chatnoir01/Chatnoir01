extends Node

## Presentation-only material for source-backed Brussels visual massing whose
## real facade/roof material identity is not yet known. This deliberately does
## not claim brick, stone, concrete, roof covering, facade module dimensions or
## measured reflectance. Geometry and height authority remain with the streamed
## source-plan renderer and its strong-height contracts.

const TARGET_NAME := "VisualCandidateBuildingMassing"
const BASE_COLOR := Color(0.60, 0.53, 0.45, 1.0)

var presentation_enabled := true
var applied_count := 0
var _material: ShaderMaterial
var _baseline_material := StandardMaterial3D.new()

func _ready() -> void:
    _baseline_material.albedo_color = BASE_COLOR
    _baseline_material.roughness = 0.90
    _baseline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    _material = _make_material()
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_scan_existing")

func _make_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.60, 0.53, 0.45, 1.0);
uniform float macro_strength = 0.085;
uniform float roof_lift = 0.045;
void fragment() {
    float macro = sin(VERTEX.x * 0.055 + VERTEX.z * 0.041) * 0.5 + 0.5;
    float wall_mix = 0.94 + macro * macro_strength;
    float up = clamp(NORMAL.y, 0.0, 1.0);
    vec3 color = base_color.rgb * wall_mix + vec3(roof_lift * up);
    ALBEDO = color;
    ROUGHNESS = mix(0.94, 0.86, up);
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("base_color", BASE_COLOR)
    material.set_shader_parameter("macro_strength", 0.085)
    material.set_shader_parameter("roof_lift", 0.045)
    return material

func _on_node_added(node: Node) -> void:
    if node is MeshInstance3D:
        call_deferred("_apply_if_target", node)

func _scan_existing() -> void:
    _scan_node(get_tree().root)

func _scan_node(node: Node) -> void:
    _apply_if_target(node)
    for child: Node in node.get_children():
        _scan_node(child)

func _apply_if_target(node: Node) -> void:
    if not is_instance_valid(node) or not node is MeshInstance3D:
        return
    if node.name != TARGET_NAME:
        return
    if not bool(node.get_meta("visual_only", false)) or bool(node.get_meta("runtime_approved", true)):
        return
    var mesh_instance := node as MeshInstance3D
    mesh_instance.material_override = _material if presentation_enabled else _baseline_material
    mesh_instance.set_meta("unclassified_massing_presentation", true)
    mesh_instance.set_meta("material_identity_claimed", false)
    applied_count += 1

func set_presentation_enabled(enabled: bool) -> void:
    presentation_enabled = enabled
    _scan_node(get_tree().root)

func get_candidate_material() -> ShaderMaterial:
    return _material

func get_baseline_material() -> StandardMaterial3D:
    return _baseline_material
