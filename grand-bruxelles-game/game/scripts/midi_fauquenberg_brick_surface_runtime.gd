extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_fauquenberg_brick_material.gd")
const IDENTITY_PATH := "res://data/visual/midi_fauquenberg_brick_material_identity.json"
const EXPECTED_SURFACES := 3
const TARGET_NAMES := ["FauquenbergBrick"]
const SUBTREE_READY_FRAMES := 30

var _targets: Array[Node] = []
var _original_materials: Dictionary = {}
var _material: ShaderMaterial
var _enabled := false
var _ready_complete := false
var _identity_failure := false
var _awaiting_station := false
var _bind_in_progress := false
var _tearing_down := false

func _ready() -> void:
    _tearing_down = false
    _awaiting_station = true
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_bind_existing_station")

func _exit_tree() -> void:
    _tearing_down = true
    _awaiting_station = false
    _bind_in_progress = false
    var tree := get_tree()
    if tree != null and tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)

func _bind_existing_station() -> void:
    if _ready_complete or _identity_failure or _bind_in_progress or _tearing_down or not is_inside_tree():
        return
    var station := get_tree().root.find_child("BruxellesMidiStation", true, false)
    if station != null:
        _bind_in_progress = true
        _apply_when_subtree_ready(station)

func _on_node_added(node: Node) -> void:
    if _ready_complete or _identity_failure or _bind_in_progress or _tearing_down or node.name != "BruxellesMidiStation":
        return
    _bind_in_progress = true
    _apply_when_subtree_ready(node)

func _apply_when_subtree_ready(station: Node) -> void:
    for _frame: int in range(SUBTREE_READY_FRAMES):
        if _tearing_down or not is_inside_tree() or not is_instance_valid(station):
            _bind_in_progress = false
            return
        _targets.clear()
        _collect_targets(station)
        if _targets.size() == EXPECTED_SURFACES:
            bind_station(station)
            return
        var tree: SceneTree = get_tree()
        if tree == null:
            _bind_in_progress = false
            return
        await tree.process_frame
        if _tearing_down or not is_inside_tree():
            _bind_in_progress = false
            return
    push_error("Midi Fauquenberg runtime: expected %d target surfaces, got %d after bounded station subtree population" % [EXPECTED_SURFACES, _targets.size()])
    _identity_failure = true
    _ready_complete = true
    _finish_waiting()

func bind_station(station: Node) -> void:
    if _tearing_down or not is_inside_tree():
        return
    _targets.clear()
    _original_materials.clear()
    _identity_failure = false
    var identity := _read_identity()
    if identity.is_empty() or not _runtime_identity_allowed(identity):
        _identity_failure = true
        _ready_complete = true
        _finish_waiting()
        return
    _collect_targets(station)
    if _targets.size() != EXPECTED_SURFACES:
        push_error("Midi Fauquenberg runtime: expected %d target surfaces, got %d" % [EXPECTED_SURFACES, _targets.size()])
        _identity_failure = true
        _ready_complete = true
        _finish_waiting()
        return
    var dims := identity.get("source_dimensions_m", {}) as Dictionary
    _material = MATERIAL_FACTORY.create(
        float(dims.get("brick_length", 0.0)),
        float(dims.get("brick_height", 0.0)),
        float(dims.get("joint_width", 0.0)),
        "Urban 9423 yellow Fauquenberg facing brick"
    )
    for target: Node in _targets:
        _original_materials[target.get_instance_id()] = _get_material(target)
    set_enhanced_material_enabled(true)
    _ready_complete = true
    _finish_waiting()
    print("Midi Fauquenberg runtime: surfaces=%d material_only=true" % _targets.size())

func _finish_waiting() -> void:
    _awaiting_station = false
    _bind_in_progress = false
    var tree := get_tree()
    if tree != null and tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)

func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _runtime_identity_allowed(identity: Dictionary) -> bool:
    if str(identity.get("schema", "")) != "grand-bruxelles-material-identity-v1":
        return false
    var target := identity.get("target", {}) as Dictionary
    if int(target.get("expected_surface_count", -1)) != EXPECTED_SURFACES:
        return false
    var dims := identity.get("source_dimensions_m", {}) as Dictionary
    if absf(float(dims.get("brick_length", 0.0)) - 0.24) > 0.0001:
        return false
    if absf(float(dims.get("brick_height", 0.0)) - 0.04) > 0.0001:
        return false
    if absf(float(dims.get("joint_width", 0.0)) - 0.02) > 0.0001:
        return false
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if str(contract.get("material_identity", "")) != "fauquenberg_yellow_facing_brick":
        return false
    if not bool(contract.get("runtime_approved", false)):
        return false
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("surface_selection_changed", true)):
        return false
    if bool(contract.get("new_architectural_detail_authored", true)) or bool(contract.get("exact_bond_pattern_claimed", true)):
        return false
    if bool(contract.get("exact_reflectance_claimed", true)) or bool(contract.get("external_texture_asset", true)):
        return false
    return true

func _collect_targets(node: Node) -> void:
    if node is MeshInstance3D and TARGET_NAMES.has(str(node.name)):
        _targets.append(node)
    for child: Node in node.get_children():
        _collect_targets(child)

func _get_material(target: Node) -> Material:
    var mesh_instance := target as MeshInstance3D
    if mesh_instance.material_override != null:
        return mesh_instance.material_override
    if mesh_instance.mesh != null:
        return mesh_instance.mesh.material
    return null

func _set_material(target: Node, material: Material) -> void:
    (target as MeshInstance3D).material_override = material

func set_enhanced_material_enabled(enabled: bool) -> void:
    _enabled = enabled
    if _material == null:
        return
    for target: Node in _targets:
        _set_material(target, _material if enabled else _original_materials.get(target.get_instance_id(), null) as Material)

func ready_complete() -> bool:
    return _ready_complete

func identity_failure() -> bool:
    return _identity_failure

func awaiting_station() -> bool:
    return _awaiting_station

func applied_surface_count() -> int:
    return _targets.size()

func enhanced_material() -> ShaderMaterial:
    return _material

func diagnostic_enabled() -> bool:
    return _enabled
