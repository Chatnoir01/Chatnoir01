extends SceneTree

const BODY_PATH := "res://civ1_body.glb"
const MAIN_SCENE_PATH := "res://game/main.tscn"
const MAIN_GROUND_PATH := NodePath("Ground")
const MAIN_CAMERA_PATH := NodePath("Player/CameraPivot/SpringArm3D/Camera3D")
const MAIN_SPRING_ARM_PATH := NodePath("Player/CameraPivot/SpringArm3D")
const WIDTH := 1280
const HEIGHT := 720
const TARGET_SAMPLES := [68, 69, 70, 71]
const POSE_BONES := ["Hips", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
const ALIASES := {
    "Hips": ["hips", "pelvis"],
    "RightUpperLeg": ["rightupperleg", "rightupleg", "rupperleg"],
    "RightLowerLeg": ["rightlowerleg", "rightleg", "rlowerleg"],
    "RightFoot": ["rightfoot", "rfoot"],
    "LeftUpperLeg": ["leftupperleg", "leftupleg", "lupperleg"],
    "LeftLowerLeg": ["leftlowerleg", "leftleg", "llowerleg"],
    "LeftFoot": ["leftfoot", "lfoot"]
}

var _bundle_path := ""
var _toe_path := ""
var _report_path := ""
var _capture_dir := ""

func _init() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    if args.size() != 4:
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:args")
        quit(2)
        return
    _bundle_path = args[0]
    _toe_path = args[1]
    _report_path = args[2]
    _capture_dir = args[3]
    call_deferred("_run")

func _norm(value: String) -> String:
    var normalized: String = value.to_lower()
    for token in [":", "/", ".", "-", "_", " "]:
        normalized = normalized.replace(token, "")
    for prefix in ["mixamorig", "armature", "general", "def"]:
        if normalized.begins_with(prefix):
            normalized = normalized.trim_prefix(prefix)
    return normalized

func _bone_index(skeleton: Skeleton3D, semantic: String) -> int:
    for index in range(skeleton.get_bone_count()):
        var normalized_name: String = _norm(skeleton.get_bone_name(index))
        for alias_value in Array(ALIASES.get(semantic, [])):
            if normalized_name == String(alias_value):
                return index
    return -1

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found: Skeleton3D = _find_skeleton(child)
        if found != null:
            return found
    return null

func _read_json(path: String) -> Variant:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    return parsed

func _v3(value: Variant) -> Vector3:
    if not value is Array or value.size() != 3:
        return Vector3(INF, INF, INF)
    return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _quat(value: Variant) -> Quaternion:
    if not value is Array or value.size() != 4:
        return Quaternion(INF, INF, INF, INF)
    return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

func _pose(record: Dictionary) -> Transform3D:
    return Transform3D(Basis(_quat(record.get("rotation_xyzw", []))), _v3(record.get("origin", [])))

func _frame_pose(frame: Dictionary, semantic: String) -> Transform3D:
    return _pose(Dictionary(frame.get("poses", {})).get(semantic, {}))

func _apply_frame(skeleton: Skeleton3D, mapping: Dictionary, frame: Dictionary) -> float:
    var error_m: float = 0.0
    for semantic in POSE_BONES:
        skeleton.set_bone_global_pose(int(mapping[semantic]), _frame_pose(frame, semantic))
    skeleton.force_update_all_bone_transforms()
    for semantic in POSE_BONES:
        error_m = max(error_m, skeleton.get_bone_global_pose(int(mapping[semantic])).origin.distance_to(_frame_pose(frame, semantic).origin))
    return error_m

func _toe_sample_map(toe_receipt: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for sample_value in Array(toe_receipt.get("samples", [])):
        if not sample_value is Dictionary:
            continue
        var sample: Dictionary = sample_value
        result[int(sample.get("sample_index", -1))] = sample
    return result

func _write_json(path: String, data: Dictionary) -> bool:
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(data, "  ") + "\n")
    file.close()
    return true

func _capture(path: String) -> bool:
    await process_frame
    await RenderingServer.frame_post_draw
    var image: Image = root.get_texture().get_image()
    return image != null and image.get_width() == WIDTH and image.get_height() == HEIGHT and image.save_png(path) == OK

func _ground_hit(world: Node3D, point: Vector3) -> Dictionary:
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.35, point + Vector3.DOWN * 0.85)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    return world.get_world_3d().direct_space_state.intersect_ray(query)

func _xz_path(records: Array, key: String) -> float:
    var path_m: float = 0.0
    for index in range(1, records.size()):
        var previous: Array = records[index - 1][key]
        var current: Array = records[index][key]
        path_m += Vector2(float(current[0]) - float(previous[0]), float(current[1]) - float(previous[1])).length()
    return path_m

func _run() -> void:
    var bundle: Variant = _read_json(_bundle_path)
    var toe_receipt: Variant = _read_json(_toe_path)
    if not bundle is Dictionary or bundle.get("schema", "") != "grand-bruxelles-civ1-skeleton-witness-bundle-v1":
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:bundle")
        quit(3)
        return
    if not toe_receipt is Dictionary or toe_receipt.get("schema", "") != "grand-bruxelles-civ1-righttoebase-pose-v1":
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:toe")
        quit(4)
        return
    if bool(bundle.get("runtime_authorized", true)) or bool(bundle.get("visual_approval_claimed", true)) or bool(bundle.get("player_view_claimed", true)):
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:bundle_rail")
        quit(5)
        return
    if not bool(toe_receipt.get("pose_coverage_ready", false)) or bool(toe_receipt.get("animation_correction_authorized", true)):
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:toe_rail")
        quit(6)
        return
    var frames: Array = bundle.get("frames", [])
    if frames.size() != 120:
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:frames")
        quit(7)
        return
    var toe_by_sample: Dictionary = _toe_sample_map(toe_receipt)
    for sample_index in TARGET_SAMPLES:
        if not toe_by_sample.has(sample_index):
            push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:toe_sample")
            quit(8)
            return

    var main_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
    var body_scene: PackedScene = load(BODY_PATH) as PackedScene
    if main_scene == null or body_scene == null:
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:assets")
        quit(9)
        return
    var canonical_main: Node = main_scene.instantiate()
    var canonical_ground: CSGBox3D = canonical_main.get_node_or_null(MAIN_GROUND_PATH) as CSGBox3D
    var canonical_camera: Camera3D = canonical_main.get_node_or_null(MAIN_CAMERA_PATH) as Camera3D
    var canonical_spring_arm: SpringArm3D = canonical_main.get_node_or_null(MAIN_SPRING_ARM_PATH) as SpringArm3D
    if canonical_ground == null or canonical_camera == null or canonical_spring_arm == null:
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:main_contract")
        canonical_main.free()
        quit(10)
        return
    if not canonical_ground.use_collision or canonical_ground.rotation.length() > 1e-8:
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:ground_contract")
        canonical_main.free()
        quit(11)
        return
    var ground_source_position: Vector3 = canonical_ground.position
    var ground_source_size: Vector3 = canonical_ground.size
    var ground_top_y: float = ground_source_position.y + ground_source_size.y * 0.5
    var player_camera_fov_deg: float = canonical_camera.fov
    var player_spring_length_m: float = canonical_spring_arm.spring_length
    var ground_copy: CSGBox3D = canonical_ground.duplicate() as CSGBox3D
    canonical_main.free()
    if ground_copy == null or not ground_copy.use_collision:
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:ground_copy")
        quit(12)
        return

    var world: Node3D = Node3D.new()
    world.name = "CIV1RightFootSameSampleGroundWitness"
    root.add_child(world)
    ground_copy.name = "CanonicalMainGround"
    world.add_child(ground_copy)
    var body: Node3D = body_scene.instantiate() as Node3D
    if body == null:
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:body")
        quit(13)
        return
    world.add_child(body)
    var skeleton: Skeleton3D = _find_skeleton(body)
    if skeleton == null:
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:skeleton")
        quit(14)
        return
    var mapping: Dictionary = {}
    for semantic in POSE_BONES:
        var bone_index: int = _bone_index(skeleton, semantic)
        if bone_index < 0:
            push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:bone_" + semantic)
            quit(15)
            return
        mapping[semantic] = bone_index

    var bilateral_floor_y: float = INF
    for frame_value in frames:
        var frame: Dictionary = frame_value
        bilateral_floor_y = min(bilateral_floor_y, _frame_pose(frame, "LeftFoot").origin.y, _frame_pose(frame, "RightFoot").origin.y)
    if not is_finite(bilateral_floor_y):
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:placement")
        quit(16)
        return
    var placement_y: float = ground_top_y - bilateral_floor_y
    body.position.y = placement_y

    var camera: Camera3D = Camera3D.new()
    camera.fov = player_camera_fov_deg
    world.add_child(camera)
    camera.current = true
    var key_light: DirectionalLight3D = DirectionalLight3D.new()
    key_light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
    key_light.light_energy = 1.4
    world.add_child(key_light)
    var fill_light: OmniLight3D = OmniLight3D.new()
    fill_light.position = Vector3(1.5, 1.2 + placement_y, 1.5)
    fill_light.omni_range = 6.0
    fill_light.light_energy = 2.5
    world.add_child(fill_light)
    root.size = Vector2i(WIDTH, HEIGHT)
    DirAccess.make_dir_recursive_absolute(_capture_dir)

    var max_pose_error_m: float = 0.0
    var samples: Array = []
    var captures: Array = []
    for sample_index in TARGET_SAMPLES:
        var frame: Dictionary = frames[sample_index]
        max_pose_error_m = max(max_pose_error_m, _apply_frame(skeleton, mapping, frame))
        await process_frame
        await physics_frame
        var rightfoot_local: Transform3D = skeleton.get_bone_global_pose(int(mapping["RightFoot"]))
        var rightfoot_world: Transform3D = skeleton.global_transform * rightfoot_local
        var toe_sample: Dictionary = toe_by_sample[sample_index]
        var toe_local: Transform3D = _pose(Dictionary(toe_sample.get("derived_righttoebase_global", {})))
        var toe_world: Transform3D = skeleton.global_transform * toe_local
        var foot_hit: Dictionary = _ground_hit(world, rightfoot_world.origin)
        var toe_hit: Dictionary = _ground_hit(world, toe_world.origin)
        if foot_hit.is_empty() or toe_hit.is_empty():
            push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:ground_ray_miss")
            quit(17)
            return
        var foot_collider: Object = foot_hit.get("collider") as Object
        var toe_collider: Object = toe_hit.get("collider") as Object
        var foot_hit_position: Vector3 = foot_hit["position"]
        var toe_hit_position: Vector3 = toe_hit["position"]
        if foot_collider == null or toe_collider == null or String(foot_collider.get("name")) != "CanonicalMainGround" or String(toe_collider.get("name")) != "CanonicalMainGround":
            push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:collider_identity")
            quit(18)
            return
        var focus: Vector3 = (rightfoot_world.origin + toe_world.origin) * 0.5
        camera.position = focus + Vector3(player_spring_length_m, 1.15, 0.0)
        camera.look_at(focus + Vector3(0.0, 0.45, 0.0), Vector3.UP)
        var capture_path: String = _capture_dir.path_join("rightfoot-ground-%03d.png" % sample_index)
        if not await _capture(capture_path):
            push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:capture")
            quit(19)
            return
        captures.append({"sample_index": sample_index, "png": capture_path, "resolution": [WIDTH, HEIGHT], "camera_semantic": "canonical_player_camera_optics_contact_diagnostic"})
        samples.append({
            "sample_index": sample_index,
            "rightfoot_world": [rightfoot_world.origin.x, rightfoot_world.origin.y, rightfoot_world.origin.z],
            "righttoebase_world": [toe_world.origin.x, toe_world.origin.y, toe_world.origin.z],
            "rightfoot_ground_hit": [foot_hit_position.x, foot_hit_position.y, foot_hit_position.z],
            "righttoebase_ground_hit": [toe_hit_position.x, toe_hit_position.y, toe_hit_position.z],
            "rightfoot_clearance_m": rightfoot_world.origin.y - foot_hit_position.y,
            "righttoebase_clearance_m": toe_world.origin.y - toe_hit_position.y,
            "rightfoot_xz": [rightfoot_world.origin.x, rightfoot_world.origin.z],
            "righttoebase_xz": [toe_world.origin.x, toe_world.origin.z],
            "ground_collider_name": String(foot_collider.get("name"))
        })

    var report: Dictionary = {
        "schema": "grand-bruxelles-civ1-rightfoot-same-sample-ground-v1",
        "diagnostic_only": true,
        "source_scene": MAIN_SCENE_PATH,
        "source_scene_instantiated": true,
        "source_ground_node": String(MAIN_GROUND_PATH),
        "ground_source_position_m": [ground_source_position.x, ground_source_position.y, ground_source_position.z],
        "ground_source_size_m": [ground_source_size.x, ground_source_size.y, ground_source_size.z],
        "ground_top_y_m": ground_top_y,
        "ground_use_collision": true,
        "ground_reference_ready": true,
        "player_camera_source_path": String(MAIN_CAMERA_PATH),
        "player_spring_arm_source_path": String(MAIN_SPRING_ARM_PATH),
        "player_camera_fov_deg": player_camera_fov_deg,
        "player_spring_length_m": player_spring_length_m,
        "player_camera_provenance_present": true,
        "capture_camera_semantic": "canonical_player_camera_optics_contact_diagnostic",
        "resolution": [WIDTH, HEIGHT],
        "sample_indices": TARGET_SAMPLES,
        "capture_count": captures.size(),
        "placement_semantic": "align_bilateral_cycle_lower_envelope_to_canonical_main_ground_top",
        "placement_y_m": placement_y,
        "max_pose_origin_error_m": max_pose_error_m,
        "rightfoot_horizontal_path_m": _xz_path(samples, "rightfoot_xz"),
        "righttoebase_horizontal_path_m": _xz_path(samples, "righttoebase_xz"),
        "same_sample_ground_evidence": true,
        "planted_contact_claimed": false,
        "quantitative_foot_slide_candidate": false,
        "animation_correction_authorized": false,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
        "player_view_claimed": false,
        "samples": samples,
        "captures": captures,
        "verdict": "AMELIORER_SAME_SAMPLE_GROUND_REFERENCE_READY_CONTACT_PHASE_NOT_YET_CLASSIFIED"
    }
    if max_pose_error_m > 0.0001 or captures.size() != TARGET_SAMPLES.size():
        report["verdict"] = "JETER_TECHNICAL_WITNESS_INTEGRITY"
    if not _write_json(_report_path, report):
        push_error("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_FAIL:report")
        quit(20)
        return
    print("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_OK ground_top=%.6f foot_path=%.6f toe_path=%.6f captures=%d" % [ground_top_y, report["rightfoot_horizontal_path_m"], report["righttoebase_horizontal_path_m"], captures.size()])
    quit(0 if report["verdict"] != "JETER_TECHNICAL_WITNESS_INTEGRITY" else 21)
