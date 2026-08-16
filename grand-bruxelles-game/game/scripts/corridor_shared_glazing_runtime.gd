extends Node

const TARGET_PREFIXES := ["CorridorWindowGlass", "CorridorShopfrontGlass"]
const MIN_DISCOVERY_FRAMES := 6
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
    if _discovery_attempts < MIN_DISCOVERY_FRAMES:
        return
    var targets: Array[MultiMeshInstance3D] = []
    _collect_targets(get_tree().root, targets)
    if targets.is_empty() and _discovery_attempts < DISCOVERY_FRAMES:
        return
    _records.clear()
    for node in targets:
        var mm := node.multimesh
        if mm == null or mm.mesh == null or not mm.mesh is BoxMesh:
            continue
        var original_mesh := mm.mesh as BoxMesh
        var original_material := original_mesh.material
        if original_material == null:
            continue
        var enhanced_material := _enhanced_for(original_material)
        var enhanced_mesh := original_mesh.duplicate() as BoxMesh
        if enhanced_mesh == null:
            continue
        enhanced_mesh.material = enhanced_material
        _records.append({
            "node": node,
            "original_mesh": original_mesh,
            "enhanced_mesh": enhanced_mesh,
            "instance_count": mm.instance_count,
            "original_size": original_mesh.size,
        })
        mm.mesh = enhanced_mesh if _enhanced_enabled else original_mesh
    _ready_complete = true
    set_process(false)

func _collect_targets(node: Node, out: Array[MultiMeshInstance3D]) -> void:
    if node is MultiMeshInstance3D and _is_target_name(node.name):
        out.append(node as MultiMeshInstance3D)
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

func applied_group_count() -> int:
    return _records.size()

func applied_instance_count() -> int:
    var total := 0
    for record in _records:
        total += int(record.get("instance_count", 0))
    return total

func shared_material_count() -> int:
    return _material_cache.size()

func set_enhanced_material_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    for record in _records:
        var node := record.get("node") as MultiMeshInstance3D
        if not is_instance_valid(node) or node.multimesh == null:
            continue
        node.multimesh.mesh = record.get("enhanced_mesh") as Mesh if enabled else record.get("original_mesh") as Mesh

func geometry_contract_intact() -> bool:
    for record in _records:
        var original := record.get("original_mesh") as BoxMesh
        var enhanced := record.get("enhanced_mesh") as BoxMesh
        if original == null or enhanced == null or original.size != enhanced.size:
            return false
    return true

func target_records() -> Array[Dictionary]:
    return _records.duplicate()
