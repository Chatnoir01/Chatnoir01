extends Node

# Production source-truth mask for the hand-built Fonsny forecourt rectangle.
# The exact-plan UrbIS StreetSurface layer is already mounted by UrbISMidiExact.
# This mask removes only the authored 18 x 174 m hero-zone slab from runtime
# pixels so the authoritative plan geometry underneath remains visible.

const TARGET_NAME := "FonsnyStationForecourt"
const EXPECTED_AUTHORED_SIZE_M := Vector3(18.0, 0.10, 174.0)

var masked_count: int = 0
var last_masked_path: NodePath = NodePath("")


func _ready() -> void:
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_mask_existing")


func _on_node_added(node: Node) -> void:
    if node.name == TARGET_NAME:
        _mask_node(node)


func _mask_existing() -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var node := scene.find_child(TARGET_NAME, true, false)
    if node != null:
        _mask_node(node)


func _mask_node(node: Node) -> void:
    if not (node is MeshInstance3D):
        return
    var mesh_node := node as MeshInstance3D
    mesh_node.visible = false
    mesh_node.set_meta("runtime_source_truth_masked", true)
    mesh_node.set_meta("mask_reason", "authored_forecourt_rectangle_replaced_by_existing_urbis_street_surface_plan")
    masked_count = 1
    last_masked_path = mesh_node.get_path()


func set_legacy_forecourt_visible(visible: bool) -> bool:
    var scene := get_tree().current_scene
    if scene == null:
        return false
    var node := scene.find_child(TARGET_NAME, true, false)
    if not (node is MeshInstance3D):
        return false
    (node as MeshInstance3D).visible = visible
    return true


func is_mask_applied() -> bool:
    var scene := get_tree().current_scene
    if scene == null:
        return false
    var node := scene.find_child(TARGET_NAME, true, false)
    return node is MeshInstance3D and not (node as MeshInstance3D).visible and bool(node.get_meta("runtime_source_truth_masked", false))
