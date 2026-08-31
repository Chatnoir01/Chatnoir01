extends SceneTree

const SOURCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const TARGET_SCENE := "res://civ1_body.glb"
const RIGHT_FOOT_ALIASES := ["rightfoot", "rfoot"]

var _output_path := ""
var _source_scene_paths: Array[String] = []

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        quit(2)
        return
    _output_path = args[0]
    call_deferred("_run")

func _scan_dir(path: String) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        return
    dir.list_dir_begin()
    while true:
        var name := dir.get_next()
        if name.is_empty():
            break
        if name.begins_with("."):
            continue
        var child := path.path_join(name)
        if dir.current_is_dir():
            _scan_dir(child)
        elif child.ends_with(SOURCE_SCENE_SUFFIX):
            _source_scene_paths.append(child)
    dir.list_dir_end()

func _collect_skeletons(node: Node, result: Array[Skeleton3D]) -> void:
    if node is Skeleton3D:
        result.append(node as Skeleton3D)
    for child in node.get_children():
        _collect_skeletons(child, result)

func _collect_players(node: Node, result: Array[AnimationPlayer]) -> void:
    if node is AnimationPlayer:
        result.append(node as AnimationPlayer)
    for child in node.get_children():
        _collect_players(child, result)

func _normalize(value: String) -> String:
    var n := value.to_lower()
    for token in [":", "/", ".", "-", "_", " "]:
        n = n.replace(token, "")
    for prefix in ["mixamorig", "armature", "general", "def"]:
        if n.begins_with(prefix):
            n = n.trim_prefix(prefix)
    return n

func _right_foot_index(skeleton: Skeleton3D) -> int:
    for i in range(skeleton.get_bone_count()):
        var normalized := _normalize(skeleton.get_bone_name(i))
        if normalized in RIGHT_FOOT_ALIASES:
            return i
    return -1

func _v3(v: Vector3) -> Array[float]:
    return [v.x, v.y, v.z]

func _bone_record(skeleton: Skeleton3D, index: int) -> Dictionary:
    var parent := skeleton.get_bone_parent(index)
    return {
        "index": index,
        "name": String(skeleton.get_bone_name(index)),
        "normalized_name": _normalize(skeleton.get_bone_name(index)),
        "parent_index": parent,
        "parent_name": String(skeleton.get_bone_name(parent)) if parent >= 0 else "",
        "local_rest_origin": _v3(skeleton.get_bone_rest(index).origin),
        "global_rest_origin": _v3(skeleton.get_bone_global_rest(index).origin),
    }

func _direct_children(skeleton: Skeleton3D, parent_index: int) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for i in range(skeleton.get_bone_count()):
        if skeleton.get_bone_parent(i) == parent_index:
            result.append(_bone_record(skeleton, i))
    return result

func _is_descendant_of(skeleton: Skeleton3D, index: int, ancestor: int) -> bool:
    var cursor := skeleton.get_bone_parent(index)
    while cursor >= 0:
        if cursor == ancestor:
            return true
        cursor = skeleton.get_bone_parent(cursor)
    return false

func _descendants(skeleton: Skeleton3D, parent_index: int) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for i in range(skeleton.get_bone_count()):
        if i != parent_index and _is_descendant_of(skeleton, i, parent_index):
            result.append(_bone_record(skeleton, i))
    return result

func _toe_like(records: Array[Dictionary]) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for record in records:
        var normalized := String(record["normalized_name"])
        if "toe" in normalized or "ball" in normalized:
            result.append(record)
    return result

func _write_payload(payload: Dictionary) -> bool:
    var out := FileAccess.open(_output_path, FileAccess.WRITE)
    if out == null:
        return false
    out.store_string(JSON.stringify(payload, "  "))
    out.close()
    return true

func _run() -> void:
    _scan_dir("res://")
    _source_scene_paths.sort()
    if _source_scene_paths.size() != 1:
        push_error("CIV1_RIGHT_FOOT_CHILD_INVENTORY_FAIL: expected one Master_Rigged scene")
        quit(3)
        return

    var source_packed := load(_source_scene_paths[0]) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        push_error("CIV1_RIGHT_FOOT_CHILD_INVENTORY_FAIL: source/target load failed")
        quit(4)
        return

    var source_instance := source_packed.instantiate()
    var target_instance := target_packed.instantiate()
    root.add_child(source_instance)
    root.add_child(target_instance)
    await process_frame

    var source_skeletons: Array[Skeleton3D] = []
    var target_skeletons: Array[Skeleton3D] = []
    _collect_skeletons(source_instance, source_skeletons)
    _collect_skeletons(target_instance, target_skeletons)
    if source_skeletons.is_empty() or target_skeletons.size() != 1:
        push_error("CIV1_RIGHT_FOOT_CHILD_INVENTORY_FAIL: unexpected skeleton inventory")
        quit(5)
        return

    var source_skeleton := source_skeletons[0]
    var players: Array[AnimationPlayer] = []
    _collect_players(source_instance, players)
    for player in players:
        var player_root := player.get_node_or_null(NodePath(player.root_node))
        if player_root is Skeleton3D:
            source_skeleton = player_root as Skeleton3D
            break
    var target_skeleton := target_skeletons[0]

    var source_right_foot := _right_foot_index(source_skeleton)
    var target_right_foot := _right_foot_index(target_skeleton)
    if source_right_foot < 0 or target_right_foot < 0:
        push_error("CIV1_RIGHT_FOOT_CHILD_INVENTORY_FAIL: RightFoot missing")
        quit(6)
        return

    var source_children := _direct_children(source_skeleton, source_right_foot)
    var target_children := _direct_children(target_skeleton, target_right_foot)
    var source_descendants := _descendants(source_skeleton, source_right_foot)
    var target_descendants := _descendants(target_skeleton, target_right_foot)
    var source_toe_like := _toe_like(source_descendants)
    var target_toe_like := _toe_like(target_descendants)

    var payload := {
        "format": "grand-bruxelles-civ1-right-foot-child-inventory-v1",
        "godot_version": Engine.get_version_info(),
        "source_skeleton_bone_count": source_skeleton.get_bone_count(),
        "target_skeleton_bone_count": target_skeleton.get_bone_count(),
        "source_right_foot": _bone_record(source_skeleton, source_right_foot),
        "target_right_foot": _bone_record(target_skeleton, target_right_foot),
        "source_right_foot_direct_children": source_children,
        "target_right_foot_direct_children": target_children,
        "source_right_foot_descendants": source_descendants,
        "target_right_foot_descendants": target_descendants,
        "source_toe_like_descendants": source_toe_like,
        "target_toe_like_descendants": target_toe_like,
        "diagnostic_only": true,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
    }
    if not _write_payload(payload):
        quit(7)
        return
    print("CIV1_RIGHT_FOOT_CHILD_INVENTORY_OK")
    quit(0)
