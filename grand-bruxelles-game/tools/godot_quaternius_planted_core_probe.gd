extends SceneTree

const SAMPLE_COUNT := 121
const TARGET_ANIMATIONS := ["UAL1_Standard/Jog_Fwd", "UAL1_Standard/Sprint"]
const REFERENCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const LEFT_FOOT_BONE := "LeftFoot"
const RIGHT_FOOT_BONE := "RightFoot"
const LOW_BAND_FRACTION := 0.10
const CORE_TRIM_FRACTION := 0.25

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

func _low_mask(samples: Array[Vector3]) -> Dictionary:
    var min_y: float = INF
    var max_y: float = -INF
    for p in samples:
        min_y = minf(min_y, p.y)
        max_y = maxf(max_y, p.y)
    var threshold: float = min_y + (max_y - min_y) * LOW_BAND_FRACTION
    var mask: Array[bool] = []
    for i in range(samples.size() - 1):
        mask.append(samples[i].y <= threshold)
    return {
        "min_y_m": min_y,
        "max_y_m": max_y,
        "vertical_range_m": max_y - min_y,
        "threshold_y_m": threshold,
        "mask": mask,
    }

func _ordered_support_windows(mask: Array[bool]) -> Array[Dictionary]:
    var segments: Array[Array] = []
    var i := 0
    while i < mask.size():
        if not mask[i]:
            i += 1
            continue
        var indices: Array[int] = []
        while i < mask.size() and mask[i]:
            indices.append(i)
            i += 1
        segments.append(indices)

    var windows: Array[Dictionary] = []
    if segments.size() >= 2 and mask[0] and mask[mask.size() - 1]:
        var wrapped: Array[int] = []
        var tail: Array = segments[segments.size() - 1]
        var head: Array = segments[0]
        for value in tail:
            wrapped.append(int(value))
        for value in head:
            wrapped.append(int(value))
        windows.append({"indices": wrapped, "wraps_cycle": true})
        for s in range(1, segments.size() - 1):
            var middle: Array[int] = []
            for value in segments[s]:
                middle.append(int(value))
            windows.append({"indices": middle, "wraps_cycle": false})
    else:
        for segment in segments:
            var copied: Array[int] = []
            for value in segment:
                copied.append(int(value))
            windows.append({"indices": copied, "wraps_cycle": false})
    return windows

func _horizontal_speed(samples: Array[Vector3], a: int, b: int, dt: float) -> float:
    var delta := Vector2(samples[b].x - samples[a].x, samples[b].z - samples[a].z).length()
    return delta / maxf(dt, 0.000001)

func _core_metrics(samples: Array[Vector3], window: Dictionary, dt: float) -> Dictionary:
    var indices: Array[int] = window["indices"]
    var trim_count := int(floor(float(indices.size()) * CORE_TRIM_FRACTION))
    trim_count = mini(trim_count, maxi((indices.size() - 2) / 2, 0))
    var core_start := trim_count
    var core_end_exclusive := indices.size() - trim_count
    var core_indices: Array[int] = []
    for pos in range(core_start, core_end_exclusive):
        core_indices.append(indices[pos])

    var core_speeds: Array[float] = []
    var edge_speeds: Array[float] = []
    for pos in range(1, indices.size()):
        var speed := _horizontal_speed(samples, indices[pos - 1], indices[pos], dt)
        if pos - 1 >= core_start and pos < core_end_exclusive:
            core_speeds.append(speed)
        else:
            edge_speeds.append(speed)

    return {
        "support_window_wraps_cycle": bool(window["wraps_cycle"]),
        "support_sample_indices": indices,
        "support_sample_count": indices.size(),
        "core_trim_fraction_each_edge": CORE_TRIM_FRACTION,
        "core_trim_sample_count_each_edge": trim_count,
        "core_sample_indices": core_indices,
        "core_sample_count": core_indices.size(),
        "core_segment_count": core_speeds.size(),
        "edge_segment_count": edge_speeds.size(),
        "core_segment_speed_mps_median": _percentile(core_speeds, 0.5),
        "core_segment_speed_mps_p90": _percentile(core_speeds, 0.9),
        "core_segment_speed_mps_max": core_speeds.max() if not core_speeds.is_empty() else 0.0,
        "edge_segment_speed_mps_median": _percentile(edge_speeds, 0.5),
        "edge_segment_speed_mps_max": edge_speeds.max() if not edge_speeds.is_empty() else 0.0,
    }

func _foot_metrics(samples: Array[Vector3], dt: float) -> Dictionary:
    var low := _low_mask(samples)
    var mask: Array[bool] = low["mask"]
    var windows := _ordered_support_windows(mask)
    var cores: Array[Dictionary] = []
    for window in windows:
        cores.append(_core_metrics(samples, window, dt))
    return {
        "min_y_m": low["min_y_m"],
        "max_y_m": low["max_y_m"],
        "vertical_range_m": low["vertical_range_m"],
        "low_band_threshold_y_m": low["threshold_y_m"],
        "support_window_count": windows.size(),
        "planted_core_windows": cores,
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
        "terminal_loop_sample_excluded_from_support_mask": true,
        "left_foot": _foot_metrics(left, dt),
        "right_foot": _foot_metrics(right, dt),
    }

func _run() -> void:
    _scan_dir("res://")
    _scene_paths.sort()
    if _scene_paths.size() != 1:
        push_error("QUATERNIUS_PLANTED_CORE_FAIL: expected one Master_Rigged scene")
        quit(3)
        return

    var packed := load(_scene_paths[0]) as PackedScene
    if packed == null:
        quit(4)
        return
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
        quit(5)
        return

    var skeleton_node := selected.get_node_or_null(NodePath(selected.root_node))
    if not (skeleton_node is Skeleton3D):
        quit(6)
        return
    var skeleton := skeleton_node as Skeleton3D

    var rows: Array[Dictionary] = []
    for name in TARGET_ANIMATIONS:
        var animation := selected.get_animation(name)
        if animation == null:
            quit(7)
            return
        rows.append(await _measure(selected, skeleton, StringName(name), animation))

    var payload := {
        "format": "grand-bruxelles-quaternius-planted-core-v1",
        "godot_version": Engine.get_version_info(),
        "reference_scene": _scene_paths[0],
        "sample_count": SAMPLE_COUNT,
        "support_definition": "source_relative_bottom_10_percent_per_foot",
        "core_definition": "middle_50_percent_of_each_ordered_support_window_trim_25_percent_each_edge",
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
        quit(8)
        return
    out.store_string(JSON.stringify(payload, "  "))
    out.close()
    print("QUATERNIUS_PLANTED_CORE_OK measurements=%d" % rows.size())
    root.remove_child(instance)
    instance.free()
    quit(0)
