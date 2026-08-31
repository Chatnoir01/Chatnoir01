extends SceneTree

const SAMPLE_COUNT := 61
const TARGET_ANIMATIONS := ["UAL1_Standard/Walk", "UAL1_Standard/Jog_Fwd", "UAL1_Standard/Sprint"]
const REFERENCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const LEFT_FOOT_BONE := "LeftFoot"
const RIGHT_FOOT_BONE := "RightFoot"
const MOTION_EPS_M := 0.00001
const ROTATION_EPS_DEG := 0.1

var _output_path := ""
var _scene_paths: Array[String] = []

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
        elif child.ends_with(REFERENCE_SCENE_SUFFIX):
            _scene_paths.append(child)
    dir.list_dir_end()

func _collect_players(node: Node, result: Array[AnimationPlayer]) -> void:
    if node is AnimationPlayer:
        result.append(node as AnimationPlayer)
    for child in node.get_children():
        _collect_players(child, result)

func _vector(v: Vector3) -> Array[float]:
    return [v.x, v.y, v.z]

func _measure_animation(player: AnimationPlayer, skeleton: Skeleton3D, animation_name: StringName, animation: Animation) -> Dictionary:
    var left_idx := skeleton.find_bone(LEFT_FOOT_BONE)
    var right_idx := skeleton.find_bone(RIGHT_FOOT_BONE)
    if left_idx < 0 or right_idx < 0:
        return {"valid": false, "reason": "foot_bones_missing"}

    var first_left_local := Vector3.ZERO
    var first_right_local := Vector3.ZERO
    var first_left_global := Vector3.ZERO
    var first_right_global := Vector3.ZERO
    var first_left_rotation := Quaternion.IDENTITY
    var first_right_rotation := Quaternion.IDENTITY
    var left_local_range := 0.0
    var right_local_range := 0.0
    var left_global_range := 0.0
    var right_global_range := 0.0
    var left_rotation_range_deg := 0.0
    var right_rotation_range_deg := 0.0
    var samples: Array[Dictionary] = []

    player.play(animation_name)
    player.advance(0.0)
    await process_frame
    for sample_index in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_index) / float(SAMPLE_COUNT - 1)
        player.seek(t, true)
        player.advance(0.0)
        await process_frame
        skeleton.force_update_all_bone_transforms()

        var left_local := skeleton.get_bone_pose_position(left_idx)
        var right_local := skeleton.get_bone_pose_position(right_idx)
        var left_rotation := skeleton.get_bone_pose_rotation(left_idx)
        var right_rotation := skeleton.get_bone_pose_rotation(right_idx)
        var left_global := skeleton.get_bone_global_pose(left_idx).origin
        var right_global := skeleton.get_bone_global_pose(right_idx).origin

        if sample_index == 0:
            first_left_local = left_local
            first_right_local = right_local
            first_left_global = left_global
            first_right_global = right_global
            first_left_rotation = left_rotation
            first_right_rotation = right_rotation

        left_local_range = maxf(left_local_range, first_left_local.distance_to(left_local))
        right_local_range = maxf(right_local_range, first_right_local.distance_to(right_local))
        left_global_range = maxf(left_global_range, first_left_global.distance_to(left_global))
        right_global_range = maxf(right_global_range, first_right_global.distance_to(right_global))
        left_rotation_range_deg = maxf(left_rotation_range_deg, rad_to_deg(first_left_rotation.angle_to(left_rotation)))
        right_rotation_range_deg = maxf(right_rotation_range_deg, rad_to_deg(first_right_rotation.angle_to(right_rotation)))

        samples.append({
            "sample_index": sample_index,
            "time_seconds": t,
            "left_local_position": _vector(left_local),
            "right_local_position": _vector(right_local),
            "left_global_position": _vector(left_global),
            "right_global_position": _vector(right_global),
            "left_local_rotation_deg_from_first": rad_to_deg(first_left_rotation.angle_to(left_rotation)),
            "right_local_rotation_deg_from_first": rad_to_deg(first_right_rotation.angle_to(right_rotation)),
        })

    player.stop()
    await process_frame
    return {
        "valid": true,
        "animation": str(animation_name),
        "length_seconds": animation.length,
        "sample_count": SAMPLE_COUNT,
        "settlement_method": "process_frame_after_scene_mount_and_each_seek",
        "left_foot_local_position_range_m": left_local_range,
        "right_foot_local_position_range_m": right_local_range,
        "left_foot_global_position_range_m": left_global_range,
        "right_foot_global_position_range_m": right_global_range,
        "left_foot_local_rotation_range_deg": left_rotation_range_deg,
        "right_foot_local_rotation_range_deg": right_rotation_range_deg,
        "bilateral_local_pose_motion": (left_local_range > MOTION_EPS_M or left_rotation_range_deg > ROTATION_EPS_DEG) and (right_local_range > MOTION_EPS_M or right_rotation_range_deg > ROTATION_EPS_DEG),
        "bilateral_global_pose_motion": left_global_range > MOTION_EPS_M and right_global_range > MOTION_EPS_M,
        "samples": samples,
    }

func _run() -> void:
    _scan_dir("res://")
    _scene_paths.sort()
    if _scene_paths.size() != 1:
        push_error("QUATERNIUS_FRAME_SETTLED_FAIL: expected one Master_Rigged scene, got %d" % _scene_paths.size())
        quit(3)
        return

    var packed := load(_scene_paths[0]) as PackedScene
    if packed == null:
        quit(4)
        return
    var instance := packed.instantiate()
    if instance == null:
        quit(5)
        return
    root.add_child(instance)
    await process_frame

    var players: Array[AnimationPlayer] = []
    _collect_players(instance, players)
    var selected_player: AnimationPlayer = null
    for player in players:
        var complete := true
        for animation_name in TARGET_ANIMATIONS:
            if not player.has_animation(animation_name):
                complete = false
                break
        if complete:
            selected_player = player
            break
    if selected_player == null:
        push_error("QUATERNIUS_FRAME_SETTLED_FAIL: no player owns the exact locomotion trio")
        quit(6)
        return

    var original_root: NodePath = selected_player.root_node
    var skeleton_node := selected_player.get_node_or_null(original_root)
    if not (skeleton_node is Skeleton3D):
        push_error("QUATERNIUS_FRAME_SETTLED_FAIL: player root does not resolve to Skeleton3D")
        quit(7)
        return
    var skeleton := skeleton_node as Skeleton3D

    var measurements: Array[Dictionary] = []
    for animation_name in TARGET_ANIMATIONS:
        var animation := selected_player.get_animation(animation_name)
        if animation == null:
            quit(8)
            return
        measurements.append(await _measure_animation(selected_player, skeleton, StringName(animation_name), animation))

    var payload := {
        "format": "grand-bruxelles-quaternius-frame-settled-pose-v1",
        "godot_version": Engine.get_version_info(),
        "reference_scene": _scene_paths[0],
        "animation_player_path": str(instance.get_path_to(selected_player)),
        "animation_root_node": str(original_root),
        "skeleton_path": str(instance.get_path_to(skeleton)),
        "sample_count": SAMPLE_COUNT,
        "settlement_method": "process_frame_after_scene_mount_and_each_seek",
        "measurements": measurements,
        "semantic_selection_allowed": false,
        "civ1_retarget_authorized": false,
        "grounding_verified": false,
        "foot_slide_verified": false,
        "visual_approval_claimed": false,
    }
    var output := FileAccess.open(_output_path, FileAccess.WRITE)
    if output == null:
        quit(9)
        return
    output.store_string(JSON.stringify(payload, "  "))
    output.close()
    print("QUATERNIUS_FRAME_SETTLED_POSE_OK measurements=%d" % measurements.size())
    root.remove_child(instance)
    instance.free()
    quit(0)
