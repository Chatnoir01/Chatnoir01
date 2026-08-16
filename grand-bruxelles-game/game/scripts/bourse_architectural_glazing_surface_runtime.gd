extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_architectural_glazing_material.gd")
const IDENTITY_PATH := "res://data/visual/bourse_architectural_glazing_material_identity.json"
const TARGET_NODE := "BoursePorticoArticulation"
const TARGET_NAMES := ["RearCentralEntry", "RearSideEntry_00", "RearSideEntry_01", "RearOvalLight_00", "RearOvalLight_01"]
const EXPECTED_SURFACES := 5

var _targets: Array[Node] = []
var _original_materials: Dictionary = {}
var _material: ShaderMaterial
var _identity_failure := false
var _enabled := false

func _ready() -> void:
    call_deferred("_bind_when_ready")

func _bind_when_ready() -> void:
    for _attempt: int in range(120):
        var portico := get_tree().root.find_child(TARGET_NODE, true, false)
        if portico != null:
            bind_portico(portico)
            return
        await get_tree().process_frame
    _identity_failure = true
    push_error("Bourse glazing runtime: %s missing" % TARGET_NODE)

func bind_portico(portico: Node) -> void:
    _targets.clear()
    _original_materials.clear()
    _identity_failure = false
    var identity := _read_identity()
    if identity.is_empty() or not _runtime_identity_allowed(identity):
        _identity_failure = true
        return
    _collect_targets(portico)
    if _targets.size() != EXPECTED_SURFACES:
        _identity_failure = true
        push_error("Bourse glazing runtime: expected %d targets, got %d" % [EXPECTED_SURFACES, _targets.size()])
        return
    _material = MATERIAL_FACTORY.create("Urban 31241 Bourse glazed doors and daylights")
    for target: Node in _targets:
        _original_materials[target.get_instance_id()] = _get_authored_material(target)
    set_enhanced_material_enabled(true)
    print("Bourse glazing runtime: surfaces=%d material_only=true" % _targets.size())

func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _surface_contract_matches(raw_names: Variant) -> bool:
    if typeof(raw_names) != TYPE_ARRAY:
        return false
    var provided: Array = raw_names as Array
    if provided.size() != TARGET_NAMES.size():
        return false
    var expected_names: Array[String] = []
    var actual_names: Array[String] = []
    for expected_name: String in TARGET_NAMES:
        expected_names.append(expected_name)
    for raw_name: Variant in provided:
        actual_names.append(str(raw_name))
    expected_names.sort()
    actual_names.sort()
    return actual_names == expected_names

func _runtime_identity_allowed(identity: Dictionary) -> bool:
    if str(identity.get("schema", "")) != "grand-bruxelles-material-identity-v1":
        return false
    var target := identity.get("target", {}) as Dictionary
    if str(target.get("runtime_node", "")) != TARGET_NODE:
        return false
    if int(target.get("expected_surface_count", -1)) != EXPECTED_SURFACES:
        return false
    if not _surface_contract_matches(target.get("surface_names", [])):
        return false
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if str(contract.get("material_identity", "")) != "architectural_glazing":
        return false
    if not bool(contract.get("runtime_approved", false)):
        return false
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("surface_selection_changed", true)):
        return false
    if bool(contract.get("pane_layout_authored", true)) or bool(contract.get("mullions_authored", true)):
        return false
    if bool(contract.get("interior_authored", true)) or bool(contract.get("external_texture_asset", true)):
        return false
    return true

func _collect_targets(node: Node) -> void:
    if TARGET_NAMES.has(str(node.name)) and (node is MeshInstance3D or node is CSGShape3D):
        _targets.append(node)
    for child: Node in node.get_children():
        _collect_targets(child)

func _get_authored_material(target: Node) -> Material:
    if target is MeshInstance3D:
        return (target as MeshInstance3D).material_override
    if target is CSGShape3D:
        return (target as CSGShape3D).material
    return null

func _get_material(target: Node) -> Material:
    if target is MeshInstance3D:
        var mesh_instance := target as MeshInstance3D
        if mesh_instance.material_override != null:
            return mesh_instance.material_override
        if mesh_instance.mesh != null:
            return mesh_instance.mesh.material
    elif target is CSGShape3D:
        return (target as CSGShape3D).material
    return null

func _set_material(target: Node, material: Material) -> void:
    if target is MeshInstance3D:
        (target as MeshInstance3D).material_override = material
    elif target is CSGShape3D:
        (target as CSGShape3D).material = material

func set_enhanced_material_enabled(enabled: bool) -> void:
    _enabled = enabled
    if _material == null:
        return
    for target: Node in _targets:
        _set_material(target, _material if enabled else _original_materials.get(target.get_instance_id(), null) as Material)

func diagnostic_target_count() -> int:
    return _targets.size()

func diagnostic_identity_failure() -> bool:
    return _identity_failure

func diagnostic_enabled() -> bool:
    return _enabled
