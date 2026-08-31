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

func _low_mask(samples: Array[Vector3]) -> Dictionary:
    var ys: Array[float] = []
    for p in samples:
        ys.append(p.y)
    var min_y: float = ys.min()
    var max_y: float = ys.max()
    var threshold: float = min_y + (max_y - min_y) * LOW_BAND_FRACTION
    var mask: Array[bool] = []
    # Keep t == animation.length for pose-range evidence, but exclude it from the
    # support/contact mask because looped playback can resolve that endpoint to t=0.
    for i in range(samples.size() - 1):
        mask.append(samples[i].y <= threshold)
    return {
        "min_y_m": min_y,
        "max_y_m": max_y,
        "vertical_range_m": max_y - min_y,
        "threshold_y_m": threshold,
        "mask": mask,
    }

func _window_metrics(samples: Array[Vector3], mask: Array[bool], dt: float) -> Dictionary:
    var windows: Array[Dictionary] = []
    var selected_count := 0
    var i := 0
    while i < mask.size():
        if not mask[i]:
            i += 1
            continue
        var start := i
        while i + 1 < mask.size() and mask[i + 1]:
            i += 1
        var end := i
        selected_count += end - start + 1
        var path_m := 0.0
        var segment_speeds: Array[float] = []
        for j in range(start + 1, end + 1):
            var horizontal := Vector2(samples[j].x - samples[j - 1].x, samples[j].z - samples[j - 1].z).length()
            path_m += horizontal
            segment_speeds.append(horizontal / maxf(dt, 0.000001))
        var displacement := Vector2(samples[end].x - samples[start].x, samples[end].z - samples[start].z).length()
        windows.append({
            "start_index": start,
            "end_index": end,
            "sample_count": end - start + 1,
            "duration_seconds": float(end - start + 1) * dt,
            "horizontal_displacement_m": displacement,
            "horizontal_path_m": path_m,
            "segment_speed_mps_median": _percentile(segment_speeds, 0.5),
            "segment_speed_mps_max": segment_speeds.max() if not segment_speeds.is_empty() else 0.0,
        })
        i += 1
    var durations: Array[float] = []
    var displacements: Array[float] = []
    var paths: Array[float] = []
    for w in windows:
        durations.append(float(w["duration_seconds"]))
        displacements.append(float(w["horizontal_displacement_m"]))
        paths.append(float(w["horizontal_path_m"]))
    return {
        "window_count": windows.size(),
        "selected_sample_count": selected_count,
        "selected_fraction": float(selected_count) / float(maxi(mask.size(), 1)),
        "duration_seconds_median": _percentile(durations, 0.5),
        "duration_seconds_max": durations.max() if not durations.is_empty() else 0.0,
        "horizontal_displacement_m_median": _percentile(displacements, 0.5),
        "horizontal_displacement_m_max": displacements.max() if not displacements.is_empty() else 0.0,
        "horizontal_path_m_median": _percentile(paths, 0.5),
        "horizontal_path_m_max": paths.max() if not paths.is_empty() else 0.0,
        "windows": windows,
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
    var left_low := _low_mask(left)
    var right_low := _low_mask(right)
    var left_mask: Array[bool] = left_low["mask"]
    var right_mask: Array[bool] = right_low["mask"]
    var overlap_count := 0
    var neither_count := 0
    var unilateral_count := 0
    for i in range(left_mask.size()):
        if left_mask[i] and right_mask[i]:
            overlap_count += 1
        elif not left_mask[i] and not right_mask[i]:
            neither_count += 1
        else:
            unilateral_count += 1
    return {
        "valid": true,
        "animation": str(animation_name),
        "length_seconds": animation.length,
        "sample_count": SAMPLE_COUNT,
        "terminal_loop_sample_excluded_from_support_mask": true,
        "left_foot": {
            "min_y_m": left_low["min_y_m"],
            "max_y_m": left_low["max_y_m"],
            "vertical_range_m": left_low["vertical_range_m"],
            "low_band_threshold_y_m": left_low["threshold_y_m"],
            "support_windows": _window_metrics(left, left_mask, dt),
        },
        "right_foot": {
            "min_y_m": right_low["min_y_m"],
            "max_y_m": right_low["max_y_m"],
            "vertical_range_m": right_low["vertical_range_m"],
            "low_band_threshold_y_m": right_low["threshold_y_m"],
            "support_windows": _window_metrics(right, right_mask, dt),
        },
        "bilateral_support_fraction": float(overlap_count) / float(maxi(left_mask.size(), 1)),
        "unilateral_support_fraction": float(unilateral_count) / float(maxi(left_mask.size(), 1)),
        "neither_low_fraction": float(neither_count) / float(maxi(left_mask.size(), 1)),
    }

func _run() -> void:
    _scan_dir("res://")
    _scene_paths.sort()
    if _scene_paths.size() != 1:
        push_error("QUATERNIUS_SUPPORT_WINDOW_FAIL: expected one Master_Rigged scene")
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
        "format": "grand-bruxelles-quaternius-support-window-v1",
        "godot_version": Engine.get_version_info(),
        "reference_scene": _scene_paths[0],
        "sample_count": SAMPLE_COUNT,
        "support_definition": "contiguous_source_relative_bottom_10_percent_windows_per_foot",
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
    print("QUATERNIUS_SUPPORT_WINDOW_OK measurements=%d" % rows.size())
    root.remove_child(instance)
    instance.free()
    quit(0)
