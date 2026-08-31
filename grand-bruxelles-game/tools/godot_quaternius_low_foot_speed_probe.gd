extends SceneTree

const SAMPLE_COUNT := 121
const TARGET_ANIMATIONS := ["UAL1_Standard/Jog_Fwd", "UAL1_Standard/Sprint"]
const REFERENCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const LEFT_FOOT_BONE := "LeftFoot"
const RIGHT_FOOT_BONE := "RightFoot"
const LOW_BAND_FRACTION := 0.10

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

func _percentile(values: Array[float], q: float) -> float:
    var copy := values.duplicate()
    copy.sort()
    if copy.is_empty():
        return 0.0
    var idx := int(round(q * float(copy.size() - 1)))
    return copy[clampi(idx, 0, copy.size() - 1)]

func _foot_metrics(samples: Array[Vector3], dt: float) -> Dictionary:
    var ys: Array[float] = []
    for p in samples:
        ys.append(p.y)
    var min_y: float = ys.min()
    var max_y: float = ys.max()
    var threshold: float = min_y + (max_y - min_y) * LOW_BAND_FRACTION
    var speeds: Array[float] = []
    var selected_indices: Array[int] = []
    for i in range(1, samples.size()):
        if samples[i].y <= threshold:
            var horizontal := Vector2(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z).length()
            speeds.append(horizontal / maxf(dt, 0.000001))
            selected_indices.append(i)
    return {
        "min_y_m": min_y,
        "max_y_m": max_y,
        "vertical_range_m": max_y - min_y,
        "low_band_fraction": LOW_BAND_FRACTION,
        "low_band_threshold_y_m": threshold,
        "low_band_sample_count": speeds.size(),
        "low_band_horizontal_speed_mps_median": _percentile(speeds, 0.5),
        "low_band_horizontal_speed_mps_p90": _percentile(speeds, 0.9),
        "low_band_horizontal_speed_mps_max": speeds.max() if not speeds.is_empty() else 0.0,
        "selected_sample_indices": selected_indices,
    }

func _measure(player: AnimationPlayer, skeleton: Skeleton3D, animation_name: StringName, animation: Animation) -> Dictionary:
    var left_idx := skeleton.find_bone(LEFT_FOOT_BONE)
    var right_idx := skeleton.find_bone(RIGHT_FOOT_BONE)
    if left_idx < 0 or right_idx < 0:
        return {"valid": false, "reason": "foot_bones_missing"}
    var left: Array[Vector3] = []
    var right: Array[Vector3] = []
    player.play(animation_name)
    player.advance(0.0)
    await process_frame
    for i in range(SAMPLE_COUNT):
        var t := animation.length * float(i) / float(SAMPLE_COUNT - 1)
        player.seek(t, true)
        player.advance(0.0)
        await process_frame
        skeleton.force_update_all_bone_transforms()
        left.append(skeleton.get_bone_global_pose(left_idx).origin)
        right.append(skeleton.get_bone_global_pose(right_idx).origin)
    player.stop()
    await process_frame
    var dt := animation.length / float(SAMPLE_COUNT - 1)
    return {
        "valid": true,
        "animation": str(animation_name),
        "length_seconds": animation.length,
        "sample_count": SAMPLE_COUNT,
        "left_foot": _foot_metrics(left, dt),
        "right_foot": _foot_metrics(right, dt),
    }

func _run() -> void:
    _scan_dir("res://")
    _scene_paths.sort()
    if _scene_paths.size() != 1:
        push_error("QUATERNIUS_LOW_FOOT_SPEED_FAIL: expected one Master_Rigged scene")
        quit(3)
        return
    var packed := load(_scene_paths[0]) as PackedScene
    var instance := packed.instantiate()
    root.add_child(instance)
    await process_frame
    var players: Array[AnimationPlayer] = []
    _collect_players(instance, players)
    var selected: AnimationPlayer = null
    for player in players:
        if player.has_animation(TARGET_ANIMATIONS[0]) and player.has_animation(TARGET_ANIMATIONS[1]):
            selected = player
            break
    if selected == null:
        quit(4)
        return
    var skeleton_node := selected.get_node_or_null(selected.root_node)
    if not (skeleton_node is Skeleton3D):
        quit(5)
        return
    var skeleton := skeleton_node as Skeleton3D
    var rows: Array[Dictionary] = []
    for name in TARGET_ANIMATIONS:
        var animation := selected.get_animation(name)
        if animation == null:
            quit(6)
            return
        rows.append(await _measure(selected, skeleton, StringName(name), animation))
    var payload := {
        "format": "grand-bruxelles-quaternius-low-foot-speed-v1",
        "godot_version": Engine.get_version_info(),
        "reference_scene": _scene_paths[0],
        "sample_count": SAMPLE_COUNT,
        "low_band_definition": "source_relative_bottom_10_percent_of_each_foot_vertical_excursion",
        "measurements": rows,
        "diagnostic_only": true,
        "world_ground_assumed": false,
        "semantic_selection_allowed": false,
        "selected_run_alias": "",
        "civ1_retarget_authorized": false,
        "grounding_verified": false,
        "foot_slide_verified": false,
        "visual_approval_claimed": false,
    }
    var out := FileAccess.open(_output_path, FileAccess.WRITE)
    if out == null:
        quit(7)
        return
    out.store_string(JSON.stringify(payload, "  "))
    out.close()
    print("QUATERNIUS_LOW_FOOT_SPEED_OK measurements=%d" % rows.size())
    root.remove_child(instance)
    instance.free()
    quit(0)
