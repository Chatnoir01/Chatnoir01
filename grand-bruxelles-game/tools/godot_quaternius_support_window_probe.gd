extends SceneTree

const SAMPLE_COUNT := 241
const TARGET_ANIMATIONS := ["UAL1_Standard/Jog_Fwd", "UAL1_Standard/Sprint"]
const REFERENCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const LEFT_FOOT_BONE := "LeftFoot"
const RIGHT_FOOT_BONE := "RightFoot"
const SUPPORT_BAND_FRACTION := 0.10

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

func _window_summary(samples: Array[Vector3], start_index: int, end_index: int, dt: float, support_plane_y: float) -> Dictionary:
    var speeds: Array[float] = []
    var horizontal_displacement := 0.0
    var min_support_distance := INF
    var max_support_distance := 0.0
    for i in range(start_index, end_index + 1):
        var support_distance := samples[i].y - support_plane_y
        min_support_distance = minf(min_support_distance, support_distance)
        max_support_distance = maxf(max_support_distance, support_distance)
        if i > start_index:
            var delta := Vector2(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z).length()
            horizontal_displacement += delta
            speeds.append(delta / maxf(dt, 0.000001))
    return {
        "start_sample_index": start_index,
        "end_sample_index": end_index,
        "sample_count": end_index - start_index + 1,
        "duration_seconds": float(end_index - start_index) * dt,
        "horizontal_path_length_m": horizontal_displacement,
        "horizontal_speed_mps_median": _percentile(speeds, 0.5),
        "horizontal_speed_mps_p90": _percentile(speeds, 0.9),
        "horizontal_speed_mps_max": speeds.max() if not speeds.is_empty() else 0.0,
        "min_distance_to_support_plane_m": min_support_distance if min_support_distance != INF else 0.0,
        "max_distance_to_support_plane_m": max_support_distance,
    }

func _foot_metrics(samples: Array[Vector3], dt: float, support_plane_y: float) -> Dictionary:
    var ys: Array[float] = []
    for p in samples:
        ys.append(p.y)
    var min_y: float = ys.min()
    var max_y: float = ys.max()
    var threshold: float = min_y + (max_y - min_y) * SUPPORT_BAND_FRACTION
    var candidate_indices: Array[int] = []
    for i in range(samples.size() - 1):
        if samples[i].y <= threshold:
            candidate_indices.append(i)
    var windows: Array[Dictionary] = []
    if not candidate_indices.is_empty():
        var window_start := candidate_indices[0]
        var previous := candidate_indices[0]
        for j in range(1, candidate_indices.size()):
            var current := candidate_indices[j]
            if current != previous + 1:
                windows.append(_window_summary(samples, window_start, previous, dt, support_plane_y))
                window_start = current
            previous = current
        windows.append(_window_summary(samples, window_start, previous, dt, support_plane_y))
    return {
        "min_y_m": min_y,
        "max_y_m": max_y,
        "vertical_range_m": max_y - min_y,
        "support_band_fraction": SUPPORT_BAND_FRACTION,
        "support_band_threshold_y_m": threshold,
        "minimum_distance_to_support_plane_m": min_y - support_plane_y,
        "candidate_sample_indices": candidate_indices,
        "candidate_window_count": windows.size(),
        "candidate_windows": windows,
        "terminal_loop_sample_excluded": true,
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
    var left_min_y: float = INF
    var right_min_y: float = INF
    for p in left:
        left_min_y = minf(left_min_y, p.y)
    for p in right:
        right_min_y = minf(right_min_y, p.y)
    var support_plane_y: float = minf(left_min_y, right_min_y)
    var dt := animation.length / float(SAMPLE_COUNT - 1)
    return {
        "valid": true,
        "animation": str(animation_name),
        "length_seconds": animation.length,
        "sample_count": SAMPLE_COUNT,
        "support_plane_y_m": support_plane_y,
        "support_plane_definition": "minimum_bilateral_source_local_foot_height_per_clip",
        "support_window_definition": "contiguous_nonterminal_samples_within_bottom_10_percent_of_foot_vertical_excursion",
        "left_foot": _foot_metrics(left, dt, support_plane_y),
        "right_foot": _foot_metrics(right, dt, support_plane_y),
    }

func _run() -> void:
    _scan_dir("res://")
    _scene_paths.sort()
    if _scene_paths.size() != 1:
        push_error("QUATERNIUS_SUPPORT_WINDOWS_FAIL: expected one Master_Rigged scene")
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
        "format": "grand-bruxelles-quaternius-support-windows-v1",
        "godot_version": Engine.get_version_info(),
        "reference_scene": _scene_paths[0],
        "sample_count": SAMPLE_COUNT,
        "support_plane_definition": "minimum_bilateral_source_local_foot_height_per_clip",
        "support_window_definition": "contiguous_nonterminal_samples_within_bottom_10_percent_of_foot_vertical_excursion",
        "measurements": rows,
        "diagnostic_only": true,
        "world_ground_assumed": false,
        "contact_verified": false,
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
    print("QUATERNIUS_SUPPORT_WINDOWS_OK measurements=%d" % rows.size())
    root.remove_child(instance)
    instance.free()
    quit(0)
