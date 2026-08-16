extends Node

const MIN_DISCOVERY_FRAMES := 6
const DISCOVERY_FRAMES := 90
const TARGET_ROOT_NAME := "GeneratedBuildings"
const TARGET_PREFIX := "Building_"

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
    var roots: Array[Node] = []
    _collect_roots(get_tree().root, roots)
    if roots.is_empty() and _discovery_attempts < DISCOVERY_FRAMES:
        return
    _records.clear()
    for root in roots:
        for child in root.get_children():
            if not child is CSGPolygon3D or not String(child.name).begins_with(TARGET_PREFIX):
                continue
            var surface := child as CSGPolygon3D
            var original := surface.material
            if original == null or not original is StandardMaterial3D:
                continue
            var standard := original as StandardMaterial3D
            var enhanced := _enhanced_for(standard)
            _records.append({
                "node": surface,
                "original_material": original,
                "enhanced_material": enhanced,
                "original_position": surface.position,
                "original_rotation": surface.rotation,
                "original_scale": surface.scale,
                "original_depth": surface.depth,
                "original_polygon": surface.polygon.duplicate(),
            })
            surface.material = enhanced if _enhanced_enabled else original
    _ready_complete = true
    set_process(false)

func _collect_roots(node: Node, out: Array[Node]) -> void:
    if String(node.name) == TARGET_ROOT_NAME:
        out.append(node)
        return
    for child in node.get_children():
        if child == self:
            continue
        _collect_roots(child, out)

func _enhanced_for(original: StandardMaterial3D) -> ShaderMaterial:
    var base := original.albedo_color
    var roughness := original.roughness
    var key := "%.4f|%.4f|%.4f|%.4f|%.4f" % [base.r, base.g, base.b, base.a, roughness]
    if _material_cache.has(key):
        return _material_cache[key] as ShaderMaterial
    var material := BrusselsUnclassifiedFacadeSurfaceMaterial.create(
        base,
        roughness,
        "OpenStreetMap building geometry + pre-existing authored generic facade palette; ODbL placement, material identity unclassified"
    )
    material.set_meta("placement_source", "pre-existing OSM Building_* production surfaces")
    _material_cache[key] = material
    return material

func ready_complete() -> bool:
    return _ready_complete

func applied_surface_count() -> int:
    return _records.size()

func shared_material_count() -> int:
    return _material_cache.size()

func set_enhanced_surface_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    for record in _records:
        var node := record.get("node") as CSGPolygon3D
        if not is_instance_valid(node):
            continue
        node.material = record.get("enhanced_material") as Material if enabled else record.get("original_material") as Material

func geometry_contract_intact() -> bool:
    for record in _records:
        var node := record.get("node") as CSGPolygon3D
        if not is_instance_valid(node):
            return false
        if node.position != record.get("original_position"):
            return false
        if node.rotation != record.get("original_rotation"):
            return false
        if node.scale != record.get("original_scale"):
            return false
        if not is_equal_approx(node.depth, float(record.get("original_depth", node.depth))):
            return false
        var original_polygon: PackedVector2Array = record.get("original_polygon", PackedVector2Array())
        if node.polygon != original_polygon:
            return false
    return true

func target_records() -> Array[Dictionary]:
    return _records.duplicate()
