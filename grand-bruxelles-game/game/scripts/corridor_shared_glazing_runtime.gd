extends Node

const TARGET_PREFIXES := ["CorridorWindowGlass", "CorridorShopfrontGlass"]
const DISCOVERY_FRAMES := 90

var _records: Array[Dictionary] = []
var _material_cache: Dictionary = {}
var _ready_complete := false
var _discovery_attempts := 0
var _enhanced_enabled := true

func _ready() -> void:
    set_process(true)

func _process(_delta: float) -> void:
    if _ready_complete:
        set_process(false)
        return
    _discovery_attempts += 1
    var targets: Array[MeshInstance3D] = []
    _collect_targets(get_tree().root, targets)
    if targets.is_empty() and _discovery_attempts < DISCOVERY_FRAMES:
        return
    _records.clear()
    for mesh in targets:
        var original := mesh.material_override
        if original == null:
            continue
        var enhanced := _enhanced_for(original)
        if enhanced == null:
            continue
        _records.append({"mesh": mesh, "original": original, "enhanced": enhanced})
        mesh.material_override = enhanced if _enhanced_enabled else original
    _ready_complete = true
    set_process(false)

func _collect_targets(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D and _is_target_name(node.name):
        out.append(node as MeshInstance3D)
    for child in node.get_children():
        if child == self:
            continue
        _collect_targets(child, out)

func _is_target_name(node_name: StringName) -> bool:
    var value := String(node_name)
    for prefix in TARGET_PREFIXES:
        if value.begins_with(prefix):
            return true
    return false

func _enhanced_for(original: Material) -> ShaderMaterial:
    var base := Color(0.10, 0.15, 0.18, 1.0)
    var roughness := 0.20
    if original is StandardMaterial3D:
        var standard := original as StandardMaterial3D
        base = standard.albedo_color
        roughness = standard.roughness
    var key := "%0.4f|%0.4f|%0.4f|%0.4f" % [base.r, base.g, base.b, roughness]
    if _material_cache.has(key):
        return _material_cache[key] as ShaderMaterial
    var material := BrusselsArchitecturalGlazingMaterial.create("Existing corridor semantic window/shopfront glazing; presentation-only response")
    var deep := Color(clampf(base.r * 0.72, 0.015, 0.30), clampf(base.g * 0.72, 0.02, 0.36), clampf(base.b * 0.72, 0.025, 0.42), 1.0)
    var sky := Color(clampf(base.r * 1.30 + 0.035, 0.05, 0.46), clampf(base.g * 1.30 + 0.05, 0.08, 0.55), clampf(base.b * 1.30 + 0.075, 0.10, 0.64), 1.0)
    material.set_shader_parameter("deep_tint", deep)
    material.set_shader_parameter("sky_tint", sky)
    material.set_shader_parameter("base_roughness", clampf(roughness * 0.78, 0.12, 0.22))
    material.set_shader_parameter("base_specular", 0.78)
    material.set_meta("material_family", "brussels_semantic_architectural_glazing")
    material.set_meta("placement_source", "pre-existing CorridorWindowGlass/CorridorShopfrontGlass semantics")
    material.set_meta("source_verified", false)
    material.set_meta("presentation_only", true)
    material.set_meta("geometry_changed", false)
    material.set_meta("pane_layout_authored", false)
    material.set_meta("exact_reflectance_claimed", false)
    _material_cache[key] = material
    return material

func ready_complete() -> bool:
    return _ready_complete

func applied_surface_count() -> int:
    return _records.size()

func shared_material_count() -> int:
    return _material_cache.size()

func set_enhanced_material_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    for record in _records:
        var mesh := record.get("mesh") as MeshInstance3D
        if not is_instance_valid(mesh):
            continue
        mesh.material_override = record.get("enhanced") as Material if enabled else record.get("original") as Material

func target_records() -> Array[Dictionary]:
    return _records.duplicate()
