extends Node

const ASSET := preload("res://game/scripts/brussels_tree_ground_contact_asset.gd")
const EXPECTED_TREE_COUNT := 266

var _root: Node3D = null
var _ground_batch: MultiMeshInstance3D = null
var _ready_complete := false
var _failed := false
var _enabled := true

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_bind_when_ready")

func _fail(message: String) -> void:
    push_error("Brussels tree ground contact runtime: %s" % message)
    _failed = true
    _ready_complete = true

func _bind_when_ready() -> void:
    var tree_runtime: Node = null
    for _attempt: int in range(180):
        tree_runtime = get_tree().root.get_node_or_null("BrusselsCorridorTreeRuntime")
        if tree_runtime != null and bool(tree_runtime.call("ready_complete")):
            break
        await get_tree().process_frame
    if tree_runtime == null or not bool(tree_runtime.call("ready_complete")) or bool(tree_runtime.call("failed")):
        _fail("corridor tree runtime unavailable")
        return

    var positions: Array = tree_runtime.call("source_positions") as Array
    var ids: Array = tree_runtime.call("source_ids") as Array
    if positions.size() != EXPECTED_TREE_COUNT or ids.size() != EXPECTED_TREE_COUNT:
        _fail("corridor tree source arrays changed")
        return

    var scene := _discover_production_scene()
    if scene == null:
        _fail("production scene missing")
        return

    var transforms: Array[Transform3D] = []
    for index: int in range(positions.size()):
        transforms.append(ASSET.ground_contact_transform(positions[index] as Vector3, int(ids[index])))

    var material := ASSET.ground_contact_material()
    var mesh := ASSET.create_ground_contact_mesh(material)
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    multimesh.visible_instance_count = transforms.size()
    for index: int in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])

    _root = Node3D.new()
    _root.name = "BrusselsTreeGroundContact"
    _root.set_meta("asset_family", ASSET.ASSET_FAMILY)
    _root.set_meta("ground_contact_revision", ASSET.GROUND_CONTACT_REVISION)
    _root.set_meta("source", "OpenStreetMap contributors via Overpass API")
    _root.set_meta("license", "ODbL-1.0")
    _root.set_meta("source_ground_treatment_claimed", false)
    _root.set_meta("source_dimensions_measured", false)
    _root.set_meta("geometry_changed_by_tree_ground_contact", false)
    scene.add_child(_root)

    _ground_batch = MultiMeshInstance3D.new()
    _ground_batch.name = "TreeGroundContact"
    _ground_batch.multimesh = multimesh
    _ground_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _root.add_child(_ground_batch)
    set_ground_contact_enabled(_enabled)
    _ready_complete = true
    print("BRUSSELS_TREE_GROUND_CONTACT_READY: trees=%d batches=1 family=%s source=OSM license=ODbL-1.0 geometry_changed=false" % [transforms.size(), ASSET.ASSET_FAMILY])

func _discover_production_scene() -> Node3D:
    var current := get_tree().current_scene
    if current is Node3D:
        return current as Node3D
    var tree_root := get_tree().root.find_child("BrusselsCorridorTrees", true, false)
    if tree_root is Node3D and tree_root.get_parent() is Node3D:
        return tree_root.get_parent() as Node3D
    var roads := get_tree().root.find_child("GeneratedRoads", true, false)
    if roads is Node3D and roads.get_parent() is Node3D:
        return roads.get_parent() as Node3D
    return null

func set_ground_contact_enabled(enabled: bool) -> void:
    _enabled = enabled
    if is_instance_valid(_ground_batch):
        _ground_batch.visible = enabled

func ground_contact_enabled() -> bool:
    return _enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func instance_count() -> int:
    return _ground_batch.multimesh.instance_count if is_instance_valid(_ground_batch) and _ground_batch.multimesh != null else 0

func batch_count() -> int:
    return 1 if is_instance_valid(_ground_batch) else 0

func source_ground_treatment_claimed() -> bool:
    return false
