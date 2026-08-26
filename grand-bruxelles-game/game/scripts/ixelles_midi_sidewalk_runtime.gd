extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_blue_stone_material.gd")
const TARGET_NAME := &"StreetSurfaces_SW"
const TARGET_PARENT_NAME := &"OfficialIxellesStreetSurfaces"
const TARGET_ROOT_NAME := &"IxellesDirectMicroSlice"
const DISABLE_ENV := "GB_IXELLES_MIDI_SIDEWALK"
const MATERIAL_OWNER := "ixelles_midi_sidewalk_runtime"

var _target: MeshInstance3D = null
var _material: ShaderMaterial = null
var _ready_complete := false
var _tree_bound := false
var _tearing_down := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _tearing_down = false
    _bind_tree()
    call_deferred("_bind_existing_target")

func _bind_tree() -> void:
    if _tearing_down or _tree_bound:
        return
    var tree := get_tree()
    if tree == null:
        return
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)
    _tree_bound = true

func _exit_tree() -> void:
    _tearing_down = true
    if not _tree_bound:
        return
    var tree := get_tree()
    if tree != null and tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)
    _tree_bound = false

func _bind_existing_target() -> void:
    if _tearing_down or not is_inside_tree():
        return
    var tree := get_tree()
    if tree == null:
        return
    var candidate := tree.root.find_child(str(TARGET_NAME), true, false)
    if candidate is MeshInstance3D and _is_valid_target(candidate):
        _apply_target(candidate as MeshInstance3D)

func _on_node_added(node: Node) -> void:
    if _tearing_down or not is_inside_tree():
        return
    if node == null or node.name != TARGET_NAME:
        return
    call_deferred("_apply_candidate", node)

func _apply_candidate(node: Node) -> void:
    if _tearing_down or not is_inside_tree():
        return
    if node is MeshInstance3D and _is_valid_target(node):
        _apply_target(node as MeshInstance3D)

func _is_valid_target(target: Node) -> bool:
    var parent := target.get_parent()
    if parent == null or parent.name != TARGET_PARENT_NAME:
        return false
    var slice_root := parent.get_parent()
    return slice_root != null and slice_root.name == TARGET_ROOT_NAME

func _ensure_material() -> void:
    if _material != null:
        return
    _material = MATERIAL_FACTORY.create(
        Color(0.095, 0.125, 0.145, 1.0),
        Color(0.255, 0.275, 0.285, 1.0),
        0.78,
        "Midi blue-stone recipe reused for Ixelles official sidewalk LABO surfaces"
    )
    _material.set_meta("recipe_source", "midi")
    _material.set_meta("zone", "ixelles")
    _material.set_meta("presentation_only", true)
    _material.set_meta("material_identity_source_backed", false)
    _material.set_meta("legacy_surface_type_semantics", "cell.street_surfaces.type")

func _apply_target(target: MeshInstance3D) -> void:
    if _tearing_down or not is_inside_tree():
        return
    if target == null or not is_instance_valid(target) or not _is_valid_target(target):
        return
    _ensure_material()
    _target = target
    _target.set_meta("shared_sidewalk_material_owner", MATERIAL_OWNER)
    _target.set_meta("legacy_surface_type", "SW")
    _target.set_meta("legacy_surface_type_semantics", "cell.street_surfaces.type")
    _target.set_meta("material_identity_source_backed", false)
    if OS.get_environment(DISABLE_ENV) != "0":
        _target.material_override = _material
    _ready_complete = true
    print("IXELLES_MIDI_SIDEWALK_READY: surfaces=1 recipe=midi geometry_changed=false enabled=%s owner=%s" % [str(OS.get_environment(DISABLE_ENV) != "0"), MATERIAL_OWNER])

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return false

func applied_surface_count() -> int:
    return 1 if _ready_complete and is_instance_valid(_target) and _target.material_override == _material else 0

func enhanced_material() -> ShaderMaterial:
    return _material
