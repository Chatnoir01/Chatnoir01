extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_architectural_glazing_material.gd")
const IDENTITY_PATH := "res://data/visual/midi_architectural_glazing_material_identity.json"
const EXACT_NAMES := ["StationLongGlassBand", "EntranceGlazing"]
const PREFIXES := ["Window_", "GroundOpening_"]
const EXPECTED_SURFACES := 340
const SUBTREE_READY_FRAMES := 30

var _targets: Array[MeshInstance3D] = []
var _original_material_overrides: Dictionary = {}
var _owned_materials: Dictionary = {}
var _material: ShaderMaterial
var _ready_complete := false
var _identity_failure := false
var _enabled := false
var _has_applied_once := false
var _identity: Dictionary = {}
var _awaiting_midi := false
var _bind_in_progress := false
var _tearing_down := false
var _watched_tree: SceneTree
var _midi_root: Node

func _ready() -> void:
    _tearing_down = false
    _identity = _read_identity()
    if _identity.is_empty():
        _ready_complete = true
        return
    _awaiting_midi = true
    _start_watching()
    call_deferred("_bind_existing_midi")

func _exit_tree() -> void:
    _tearing_down = true
    _awaiting_midi = false
    _bind_in_progress = false
    _release_material_ownership()
    _midi_root = null
    _stop_watching()

func _start_watching() -> void:
    if _tearing_down or not is_inside_tree():
        return
    var tree: SceneTree = get_tree()
    if tree == null:
        return
    if _watched_tree != null and _watched_tree != tree:
        _stop_watching()
    _watched_tree = tree
    if not _watched_tree.node_added.is_connected(_on_node_added):
        _watched_tree.node_added.connect(_on_node_added)
    if not _watched_tree.node_removed.is_connected(_on_node_removed):
        _watched_tree.node_removed.connect(_on_node_removed)

func _stop_watching() -> void:
    if _watched_tree != null and is_instance_valid(_watched_tree):
        if _watched_tree.node_added.is_connected(_on_node_added):
            _watched_tree.node_added.disconnect(_on_node_added)
        if _watched_tree.node_removed.is_connected(_on_node_removed):
            _watched_tree.node_removed.disconnect(_on_node_removed)
    _watched_tree = null

func _bind_existing_midi() -> void:
    if _identity_failure or _bind_in_progress or _tearing_down or not is_inside_tree():
        return
    if _midi_root != null and is_instance_valid(_midi_root) and _midi_root.is_inside_tree():
        return
    var tree: SceneTree = get_tree()
    if tree == null:
        return
    var midi := tree.root.get_node_or_null("GrandBruxelles/MidiHeroZone")
    if midi == null:
        midi = tree.root.find_child("MidiHeroZone", true, false)
    if midi != null:
        _bind_in_progress = true
        _apply_when_subtree_ready(midi)

func _on_node_added(node: Node) -> void:
    if _identity_failure or _bind_in_progress or _tearing_down or node.name != "MidiHeroZone":
        return
    if _midi_root != null and is_instance_valid(_midi_root) and _midi_root.is_inside_tree():
        return
    _bind_in_progress = true
    _apply_when_subtree_ready(node)

func _on_node_removed(node: Node) -> void:
    if _tearing_down or _midi_root == null:
        return
    var removed_bound_root := node == _midi_root
    if not removed_bound_root and is_instance_valid(_midi_root):
        removed_bound_root = node.is_ancestor_of(_midi_root)
    if not removed_bound_root:
        return
    _release_material_ownership()
    _midi_root = null
    _ready_complete = false
    _identity_failure = false
    _awaiting_midi = true
    _bind_in_progress = false
    _start_watching()
    call_deferred("_bind_existing_midi")

func _apply_when_subtree_ready(midi: Node) -> void:
    for _frame: int in range(SUBTREE_READY_FRAMES):
        if _tearing_down or not is_inside_tree() or not is_instance_valid(midi):
            _bind_in_progress = false
            return
        _targets.clear()
        _collect_targets(midi)
        if _targets.size() == EXPECTED_SURFACES:
            _midi_root = midi
            _apply_material()
            return
        var tree: SceneTree = get_tree()
        if tree == null:
            _bind_in_progress = false
            return
        await tree.process_frame
        if _tearing_down or not is_inside_tree():
            _bind_in_progress = false
            return
    push_error("Midi glazing runtime: expected %d verified glazing surfaces, got %d after bounded Midi subtree population" % [EXPECTED_SURFACES, _targets.size()])
    _identity_failure = true
    _ready_complete = true
    _finish_waiting()

func _apply_material() -> void:
    _material = MATERIAL_FACTORY.create("Midi Urban 9423 architectural glazing")
    for target in _targets:
        var instance_id := target.get_instance_id()
        _original_material_overrides[instance_id] = target.material_override
    if _runtime_identity_allowed(_identity):
        var desired_enabled := _enabled if _has_applied_once else true
        _has_applied_once = true
        set_enhanced_material_enabled(desired_enabled)
    _ready_complete = true
    _finish_waiting()

func _finish_waiting() -> void:
    _awaiting_midi = false
    _bind_in_progress = false

func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH):
        push_error("Midi glazing runtime: material identity missing")
        _identity_failure = true
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Midi glazing runtime: material identity invalid")
        _identity_failure = true
        return {}
    return parsed as Dictionary

func _runtime_identity_allowed(identity: Dictionary) -> bool:
    if str(identity.get("schema", "")) != "grand-bruxelles-material-identity-v1":
        return false
    var target := identity.get("target", {}) as Dictionary
    if int(target.get("expected_surface_count", -1)) != EXPECTED_SURFACES:
        return false
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if str(contract.get("material_identity", "")) != "architectural_glazing":
        return false
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("new_location_specific_placement", true)):
        return false
    if bool(contract.get("pane_layout_authored", true)) or bool(contract.get("interior_authored", true)):
        return false
    if bool(contract.get("exact_reflectance_claimed", true)):
        return false
    return bool(contract.get("runtime_approved", false))

func _is_target_name(node_name: String) -> bool:
    if node_name in EXACT_NAMES:
        return true
    for prefix in PREFIXES:
        if node_name.begins_with(prefix):
            return true
    return false

func _collect_targets(node: Node) -> void:
    if node is MeshInstance3D and _is_target_name(node.name):
        _targets.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_targets(child)

func _restore_owned_materials() -> void:
    for target in _targets:
        if not is_instance_valid(target):
            continue
        var instance_id := target.get_instance_id()
        var owned: Material = _owned_materials.get(instance_id) as Material
        if owned != null and target.material_override == owned:
            target.material_override = _original_material_overrides.get(instance_id) as Material

func _release_material_ownership() -> void:
    _restore_owned_materials()
    _owned_materials.clear()
    _original_material_overrides.clear()
    _targets.clear()
    _material = null

func set_enhanced_material_enabled(enabled: bool) -> void:
    if enabled and not _runtime_identity_allowed(_identity):
        _enabled = false
        return
    _enabled = enabled
    if _material == null:
        return
    for target in _targets:
        if not is_instance_valid(target):
            continue
        var instance_id := target.get_instance_id()
        var baseline: Material = _original_material_overrides.get(instance_id) as Material
        var owned: Material = _owned_materials.get(instance_id) as Material
        if enabled:
            if target.material_override == baseline or (owned != null and target.material_override == owned):
                target.material_override = _material
                _owned_materials[instance_id] = _material
        elif owned != null and target.material_override == owned:
            target.material_override = baseline

func apply_candidate_for_validation() -> void:
    set_enhanced_material_enabled(true)

func enhanced_material_enabled() -> bool:
    return _enabled

func ready_complete() -> bool:
    return _ready_complete

func identity_failure() -> bool:
    return _identity_failure

func awaiting_midi() -> bool:
    return _awaiting_midi

func applied_surface_count() -> int:
    return _targets.size() if _ready_complete and not _identity_failure else 0

func enhanced_material() -> ShaderMaterial:
    return _material
