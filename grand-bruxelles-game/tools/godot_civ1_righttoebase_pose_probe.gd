extends SceneTree

const FOOT := "mixamorig_RightFoot"
const TOE := "mixamorig_RightToeBase"
const TARGET_SAMPLES := [68, 69, 70, 71]
const REQUIRED_FRAME_COUNT := 120
const MAX_SOURCE_KEY_TIME_SPREAD := 0.000001

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:args"); quit(2); return
    var bundle: Variant = _read_json(args[0])
    if not bundle is Dictionary or bundle.get("schema", "") != "grand-bruxelles-civ1-skeleton-witness-bundle-v1":
        push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:bundle"); quit(3); return
    var frames: Array = bundle.get("frames", [])
    if frames.size() != REQUIRED_FRAME_COUNT:
        push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:frame-count"); quit(4); return
    var packed := load("res://civ1_animated.glb") as PackedScene
    if packed == null:
        push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:animated-source"); quit(5); return
    var body := packed.instantiate(); get_root().add_child(body); await process_frame
    var skeleton := _find_skeleton(body)
    var player := _find_animation_player(body)
    if skeleton == null or player == null:
        push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:animation-rig"); quit(6); return
    var foot := skeleton.find_bone(FOOT)
    var toe := skeleton.find_bone(TOE)
    if foot < 0 or toe < 0 or skeleton.get_bone_parent(toe) != foot:
        push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:direct-chain"); quit(7); return
    var source := _find_source_animation(player)
    if source.is_empty():
        push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:no-120-key-rightfoot-animation"); quit(8); return
    var animation_name := StringName(source["animation_name"])
    var key_times: Array = source["key_times"]
    var samples: Array = []
    for sample_index in TARGET_SAMPLES:
        var frame := frames[sample_index] as Dictionary
        if int(frame.get("sample_index", -1)) != sample_index:
            push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:bundle-index"); quit(9); return
        var poses := frame.get("poses", {}) as Dictionary
        if not poses.has("RightFoot") or poses.has("RightToeBase"):
            push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:coverage-contract"); quit(10); return
        player.play(animation_name)
        player.seek(float(key_times[sample_index]), true)
        player.advance(0.0)
        skeleton.force_update_all_bone_transforms()
        var source_foot := skeleton.get_bone_global_pose(foot)
        var source_toe := skeleton.get_bone_global_pose(toe)
        var source_relative := source_foot.affine_inverse() * source_toe
        var corrected_foot := _pose(poses["RightFoot"] as Dictionary)
        var corrected_toe := corrected_foot * source_relative
        samples.append({
            "sample_index":sample_index,
            "source_time_s":float(key_times[sample_index]),
            "source_rightfoot_global":_transform_record(source_foot),
            "source_righttoebase_global":_transform_record(source_toe),
            "source_righttoebase_relative_to_rightfoot":_transform_record(source_relative),
            "validated_rightfoot_global":_transform_record(corrected_foot),
            "derived_righttoebase_global":_transform_record(corrected_toe)
        })
    var report := {
        "schema":"grand-bruxelles-civ1-righttoebase-pose-v1",
        "diagnostic_only":true,
        "samples":samples,
        "sample_indices":TARGET_SAMPLES,
        "frame_count":REQUIRED_FRAME_COUNT,
        "source_animation_name":str(animation_name),
        "source_rightfoot_key_count":key_times.size(),
        "source_semantic":"source-authored RightToeBase relative transform composed onto validated reconstructed RightFoot global pose",
        "righttoebase_direct_child_of_rightfoot":true,
        "pose_coverage_ready":true,
        "full_vertex_influence_basis_required":true,
        "skinning_input_complete":false,
        "bone_local_witness_authorized":false,
        "contact_phase_ready":false,
        "quantitative_foot_slide_candidate":false,
        "animation_correction_authorized":false,
        "runtime_authorized":false,
        "visual_approval_claimed":false,
        "player_view_claimed":false
    }
    if not _write_json(args[1], report):
        push_error("CIV1_RIGHTTOEBASE_POSE_FAIL:output"); quit(11); return
    print("CIV1_RIGHTTOEBASE_POSE_OK animation=", animation_name, " samples=", TARGET_SAMPLES)
    quit(0)

func _find_source_animation(player: AnimationPlayer) -> Dictionary:
    for name in player.get_animation_list():
        var anim := player.get_animation(name)
        if anim == null: continue
        for track in range(anim.get_track_count()):
            var path := str(anim.track_get_path(track))
            if FOOT not in path: continue
            var count := anim.track_get_key_count(track)
            if count < REQUIRED_FRAME_COUNT: continue
            var times: Array = []
            for i in range(REQUIRED_FRAME_COUNT): times.append(anim.track_get_key_time(track, i))
            var monotonic := true
            for i in range(1, times.size()):
                if float(times[i]) <= float(times[i - 1]) + MAX_SOURCE_KEY_TIME_SPREAD:
                    monotonic = false; break
            if monotonic:
                return {"animation_name":name, "key_times":times, "track_path":path}
    return {}

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D: return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null: return found
    return null

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer: return node
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found != null: return found
    return null

func _read_json(path: String) -> Variant:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null: return null
    var value: Variant = JSON.parse_string(f.get_as_text()); f.close(); return value

func _v3(v: Variant) -> Vector3:
    if not v is Array or v.size() != 3: return Vector3(INF, INF, INF)
    return Vector3(float(v[0]), float(v[1]), float(v[2]))

func _quat(v: Variant) -> Quaternion:
    if not v is Array or v.size() != 4: return Quaternion(INF, INF, INF, INF)
    return Quaternion(float(v[0]), float(v[1]), float(v[2]), float(v[3])).normalized()

func _pose(rec: Dictionary) -> Transform3D:
    return Transform3D(Basis(_quat(rec.get("rotation_xyzw", []))), _v3(rec.get("origin", [])))

func _transform_record(t: Transform3D) -> Dictionary:
    var q: Quaternion = t.basis.get_rotation_quaternion().normalized()
    return {"origin":[t.origin.x,t.origin.y,t.origin.z], "rotation_xyzw":[q.x,q.y,q.z,q.w]}

func _write_json(path: String, data: Dictionary) -> bool:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null: return false
    f.store_string(JSON.stringify(data, "  ")); f.close(); return true
