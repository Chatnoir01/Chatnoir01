extends SceneTree

const BODY_PATH := "res://civ1_body.glb"
const HEAD_PATH := "res://vitruvian_head.glb"
const HEAD_BONE := "mixamorig_Head"
const WIDTH := 1280
const HEIGHT := 720
const POSE_BONES := ["Hips", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
const ALIASES := {
    "Hips": ["hips", "pelvis"],
    "LeftUpperLeg": ["leftupperleg", "leftupleg", "lupperleg"],
    "LeftLowerLeg": ["leftlowerleg", "leftleg", "llowerleg"],
    "LeftFoot": ["leftfoot", "lfoot"],
    "RightUpperLeg": ["rightupperleg", "rightupleg", "rupperleg"],
    "RightLowerLeg": ["rightlowerleg", "rightleg", "rlowerleg"],
    "RightFoot": ["rightfoot", "rfoot"],
}

var _bundle_path := ""
var _report_path := ""
var _capture_dir := ""

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 3:
        push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: expected bundle report capture_dir")
        quit(2); return
    _bundle_path = args[0]
    _report_path = args[1]
    _capture_dir = args[2]
    call_deferred("_run")

func _normalize(value: String) -> String:
    var n := value.to_lower()
    for token in [":", "/", ".", "-", "_", " "]:
        n = n.replace(token, "")
    for prefix in ["mixamorig", "armature", "general", "def"]:
        if n.begins_with(prefix): n = n.trim_prefix(prefix)
    return n

func _bone_index(skeleton: Skeleton3D, semantic: String) -> int:
    var aliases: Array = ALIASES.get(semantic, [_normalize(semantic)])
    for i in range(skeleton.get_bone_count()):
        var normalized := _normalize(skeleton.get_bone_name(i))
        for alias in aliases:
            if normalized == String(alias): return i
    return -1

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D: return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null: return found
    return null

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D: out.append(node as MeshInstance3D)
    for child in node.get_children(): _collect_meshes(child, out)

func _read_json(path: String) -> Variant:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null: return null
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    f.close(); return parsed

func _v3(value: Variant) -> Vector3:
    if not value is Array or value.size() != 3: return Vector3(INF, INF, INF)
    return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _quat(value: Variant) -> Quaternion:
    if not value is Array or value.size() != 4: return Quaternion(INF, INF, INF, INF)
    return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

func _pose(rec: Dictionary) -> Transform3D:
    return Transform3D(Basis(_quat(rec.get("rotation_xyzw", []))), _v3(rec.get("origin", [])))

func _write_json(path: String, data: Dictionary) -> bool:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null: return false
    f.store_string(JSON.stringify(data, "  "))
    f.close(); return true

func _frame_pose(frame: Dictionary, semantic: String) -> Transform3D:
    return _pose(Dictionary(frame.get("poses", {})).get(semantic, {}))

func _support_band_path(frames: Array, semantic: String) -> Dictionary:
    var ys: Array[float] = []
    for f in frames: ys.append(_frame_pose(f, semantic).origin.y)
    var lo := ys.min()
    var hi := ys.max()
    var threshold: float = lo + (hi - lo) * 0.10
    var path := 0.0
    var count := 0
    var previous := Vector3.ZERO
    var have_previous := false
    for f in frames:
        var p := _frame_pose(f, semantic).origin
        if p.y <= threshold:
            count += 1
            if have_previous: path += Vector2(p.x - previous.x, p.z - previous.z).length()
            previous = p; have_previous = true
        else:
            have_previous = false
    return {"min_y_m": lo, "max_y_m": hi, "band_threshold_y_m": threshold, "sample_count": count, "horizontal_path_m": path}

func _apply_frame(skeleton: Skeleton3D, mapping: Dictionary, frame: Dictionary) -> float:
    var max_error := 0.0
    var poses: Dictionary = frame.get("poses", {})
    for semantic in POSE_BONES:
        if not poses.has(semantic): return INF
        skeleton.set_bone_global_pose(int(mapping[semantic]), _pose(poses[semantic]))
    skeleton.force_update_all_bone_transforms()
    for semantic in POSE_BONES:
        var wanted := _pose(poses[semantic])
        var actual := skeleton.get_bone_global_pose(int(mapping[semantic]))
        max_error = max(max_error, actual.origin.distance_to(wanted.origin))
    return max_error

func _capture(path: String) -> bool:
    await process_frame; await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    return image != null and image.get_width() == WIDTH and image.get_height() == HEIGHT and image.save_png(path) == OK

func _run() -> void:
    var bundle = _read_json(_bundle_path)
    if not bundle is Dictionary or bundle.get("schema", "") != "grand-bruxelles-civ1-skeleton-witness-bundle-v1":
        push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: bundle schema"); quit(3); return
    if bool(bundle.get("runtime_authorized", true)) or bool(bundle.get("visual_approval_claimed", true)) or bool(bundle.get("player_view_claimed", true)):
        push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: production rail"); quit(4); return
    var frames: Array = bundle.get("frames", [])
    if frames.size() != 120:
        push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: frame count"); quit(5); return

    var body_scene := load(BODY_PATH) as PackedScene
    var head_scene := load(HEAD_PATH) as PackedScene
    if body_scene == null or head_scene == null:
        push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: imported assets"); quit(6); return
    var world := Node3D.new(); world.name = "CIV1DynamicFullCharacter"; root.add_child(world)
    var body := body_scene.instantiate(); world.add_child(body)
    var skeleton := _find_skeleton(body)
    if skeleton == null:
        push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: skeleton"); quit(7); return
    var mapping := {}
    for semantic in POSE_BONES:
        var idx := _bone_index(skeleton, semantic)
        if idx < 0:
            push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: missing " + semantic); quit(8); return
        mapping[semantic] = idx
    var head_idx := skeleton.find_bone(HEAD_BONE)
    if head_idx < 0:
        push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: head bone"); quit(9); return

    var attachment := BoneAttachment3D.new(); attachment.name = "HeadAttach"; skeleton.add_child(attachment); attachment.bone_idx = head_idx
    var head_rig := Node3D.new(); head_rig.name = "HeadRig"; attachment.add_child(head_rig); head_rig.global_transform = Transform3D.IDENTITY
    var head := head_scene.instantiate(); head.name = "Head"; head_rig.add_child(head)

    var body_meshes: Array[MeshInstance3D] = []; var head_meshes: Array[MeshInstance3D] = []
    _collect_meshes(body, body_meshes); _collect_meshes(head, head_meshes)
    var head_surfaces := 0; var head_materials := 0
    for mi in head_meshes:
        if mi.mesh == null: continue
        for s in range(mi.mesh.get_surface_count()):
            head_surfaces += 1
            if mi.get_active_material(s) != null: head_materials += 1
    if body_meshes.is_empty() or head_meshes.is_empty() or head_surfaces == 0 or head_materials != head_surfaces:
        push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: mesh/material integrity"); quit(10); return

    var camera := Camera3D.new(); camera.position = Vector3(0.0, 1.05, 3.2); camera.fov = 38.0; world.add_child(camera); camera.look_at(Vector3(0.0, 0.95, 0.0)); camera.current = true
    var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-35.0, -25.0, 0.0); key.light_energy = 1.4; world.add_child(key)
    var fill := OmniLight3D.new(); fill.position = Vector3(1.2, 1.4, 2.0); fill.omni_range = 6.0; fill.light_energy = 3.0; world.add_child(fill)
    root.size = Vector2i(WIDTH, HEIGHT)

    var max_pose_error := 0.0
    var max_head_follow_error := 0.0
    var pelvis_min := INF; var pelvis_max := -INF; var max_pelvis_frame := 0
    var max_knee_correction := -1.0; var max_knee_frame := 0
    var min_right_foot_y := INF; var right_contact_frame := 0
    for i in range(frames.size()):
        var frame: Dictionary = frames[i]
        max_pose_error = max(max_pose_error, _apply_frame(skeleton, mapping, frame))
        await process_frame
        var head_pose := skeleton.get_bone_global_pose(head_idx)
        var expected_head_origin := skeleton.to_global(head_pose.origin)
        max_head_follow_error = max(max_head_follow_error, attachment.global_transform.origin.distance_to(expected_head_origin))
        var pelvis_y := _frame_pose(frame, "Hips").origin.y
        if pelvis_y < pelvis_min: pelvis_min = pelvis_y
        if pelvis_y > pelvis_max: pelvis_max = pelvis_y; max_pelvis_frame = i
        var knee_corr := max(float(frame.get("right_knee_correction_m", 0.0)), float(frame.get("left_knee_correction_m", 0.0)))
        if knee_corr > max_knee_correction: max_knee_correction = knee_corr; max_knee_frame = i
        var right_y := _frame_pose(frame, "RightFoot").origin.y
        if right_y < min_right_foot_y: min_right_foot_y = right_y; right_contact_frame = i

    var capture_frames: Array[int] = []
    for candidate in [max_knee_frame, max_pelvis_frame, right_contact_frame]:
        if not capture_frames.has(candidate): capture_frames.append(candidate)
    DirAccess.make_dir_recursive_absolute(_capture_dir)
    var captures: Array = []
    for idx in capture_frames:
        var frame: Dictionary = frames[idx]
        var err := _apply_frame(skeleton, mapping, frame)
        max_pose_error = max(max_pose_error, err)
        var png := _capture_dir.path_join("frame-%03d.png" % idx)
        if not await _capture(png):
            push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: capture"); quit(11); return
        captures.append({"sample_index": idx, "png": png, "pelvis_delta_mm": int(frame.get("pelvis_delta_mm", 0))})

    var right_support := _support_band_path(frames, "RightFoot")
    var left_support := _support_band_path(frames, "LeftFoot")
    var report := {
        "schema": "grand-bruxelles-civ1-dynamic-full-character-v1",
        "diagnostic_only": true,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
        "player_view_claimed": false,
        "resolution": [WIDTH, HEIGHT],
        "frame_count": frames.size(),
        "body_mesh_count": body_meshes.size(),
        "head_mesh_count": head_meshes.size(),
        "head_surface_count": head_surfaces,
        "head_material_surface_count": head_materials,
        "head_attachment_bone": HEAD_BONE,
        "max_pose_origin_error_m": max_pose_error,
        "max_head_follow_error_m": max_head_follow_error,
        "pelvis_vertical_range_m": pelvis_max - pelvis_min,
        "max_knee_correction_m": max_knee_correction,
        "right_support_band": right_support,
        "left_support_band": left_support,
        "captures": captures,
        "verdict": "REQUIRE_HUMAN_DYNAMIC_VISUAL_REVIEW"
    }
    if max_pose_error > 0.0001 or max_head_follow_error > 0.0001:
        report["verdict"] = "JETER_DYNAMIC_TECHNICAL_DRIFT"
    if not _write_json(_report_path, report):
        push_error("CIV1_DYNAMIC_FULL_CHARACTER_FAIL: report"); quit(12); return
    print("CIV1_DYNAMIC_FULL_CHARACTER_OK pose_error=%.9f head_error=%.9f pelvis_range=%.6f knee=%.6f" % [max_pose_error, max_head_follow_error, pelvis_max - pelvis_min, max_knee_correction])
    quit(0 if report["verdict"] != "JETER_DYNAMIC_TECHNICAL_DRIFT" else 13)
