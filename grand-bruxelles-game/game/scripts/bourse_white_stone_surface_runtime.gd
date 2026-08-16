extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_white_stone_material.gd")
const IDENTITY_PATH := "res://data/visual/bourse_white_stone_material_identity.json"
const EXPECTED_SURFACES := 24
const EXACT_NAMES := ["PorticoEntablature", "RearCentralEntryLintel"]
const PREFIXES := ["Column_", "RearPilaster_"]

var _targets: Array[Node] = []
var _original_materials: Dictionary = {}
var _material: ShaderMaterial
var _enabled := false
var _ready_complete := false
var _identity_failure := false


func _ready() -> void:
    call_deferred("_bind_when_ready")


func _bind_when_ready() -> void:
    for _attempt: int in range(120):
        var portico := get_tree().root.find_child("BoursePorticoArticulation", true, false)
        if portico != null:
            bind_portico(portico)
            return
        await get_tree().process_frame
    _identity_failure = true
    _ready_complete = true
    push_error("Bourse white-stone runtime: BoursePorticoArticulation missing")


func bind_portico(portico: Node) -> void:
    _targets.clear()
    _original_materials.clear()
    _identity_failure = false
    var identity := _read_identity()
    if identity.is_empty() or not _identity_is_safe(identity):
        _identity_failure = true
        _ready_complete = true
        return
    _collect_targets(portico)
    if _targets.size() != EXPECTED_SURFACES:
        push_error("Bourse white-stone runtime: expected %d target surfaces, got %d" % [EXPECTED_SURFACES, _targets.size()])
        _identity_failure = true
        _ready_complete = true
        return
    _material = MATERIAL_FACTORY.create(
        Color(0.70, 0.69, 0.64, 1.0),
        Color(0.84, 0.82, 0.75, 1.0),
        0.82,
        "Bourse Urban 31241 white-stone facades"
    )
    for target: Node in _targets:
        _original_materials[target.get_instance_id()] = _get_material(target)
    set_enhanced_material_enabled(true)
    _ready_complete = true
    print("Bourse white-stone runtime: surfaces=%d presentation_only=true" % _targets.size())


func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH):
        push_error("Bourse white-stone runtime: material identity missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Bourse white-stone runtime: invalid material identity")
        return {}
    return parsed as Dictionary


func _identity_is_safe(identity: Dictionary) -> bool:
    if str(identity.get("schema", "")) != "grand-bruxelles-material-identity-v1":
        return false
    var target := identity.get("target", {}) as Dictionary
    if int(target.get("expected_surface_count", -1)) != EXPECTED_SURFACES:
        return false
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if str(contract.get("material_identity", "")) != "white_stone":
        return false
    if bool(contract.get("geometry_changed", true)):
        return false
    if bool(contract.get("candidate_geometry_promoted", true)):
        return false
    if bool(contract.get("masonry_joints_authored", true)) or bool(contract.get("openings_authored", true)):
        return false
    if bool(contract.get("exact_stone_species_claimed", true)) or bool(contract.get("exact_reflectance_claimed", true)):
        return false
    return true


func _is_target_name(node_name: String) -> bool:
    if node_name in EXACT_NAMES:
        return true
    for prefix: String in PREFIXES:
        if node_name.begins_with(prefix):
            return true
    return false


func _collect_targets(node: Node) -> void:
    if (node is MeshInstance3D or node is CSGBox3D) and _is_target_name(node.name):
        _targets.append(node)
    for child: Node in node.get_children():
        _collect_targets(child)


func _get_material(target: Node) -> Material:
    if target is MeshInstance3D:
        var mesh_instance := target as MeshInstance3D
        if mesh_instance.material_override != null:
            return mesh_instance.material_override
        if mesh_instance.mesh != null:
            return mesh_instance.mesh.material
    elif target is CSGBox3D:
        return (target as CSGBox3D).material
    return null


func _set_material(target: Node, material: Material) -> void:
    if target is MeshInstance3D:
        (target as MeshInstance3D).material_override = material
    elif target is CSGBox3D:
        (target as CSGBox3D).material = material


func set_enhanced_material_enabled(enabled: bool) -> void:
    _enabled = enabled
    if _material == null:
        return
    for target: Node in _targets:
        if enabled:
            _set_material(target, _material)
        else:
            _set_material(target, _original_materials.get(target.get_instance_id(), null) as Material)


func diagnostic_target_count() -> int:
    return _targets.size()


func diagnostic_enabled() -> bool:
    return _enabled


func diagnostic_ready_complete() -> bool:
    return _ready_complete


func diagnostic_identity_failure() -> bool:
    return _identity_failure
