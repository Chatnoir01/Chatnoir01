extends SceneTree

const TARGET_SCENE := "res://civ1_body.glb"
const WIDTH := 1280
const HEIGHT := 720
const POSE_BONES := [
    "Hips",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
]
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
var _png_path := ""
var _report_path := ""

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 3:
        push_error("CIV1_SKELETON_WITNESS_FAIL: expected bundle, png, report")
        quit(2)
        return
    _bundle_path = args[0]
    _png_path = args[1]
    _report_path = args[2]
    call_deferred("_run")

func _normalize(value: String) -> String:
    var n := value.to_lower()
    for token in [":", "/", ".", "-", "_", " "]:
        n = n.replace(token, "")
    for prefix in ["mixamorig", "armature", "general", "def"]:
        if n.begins_with(prefix):
            n = n.trim_prefix(prefix)
    return n

func _bone_index(skeleton: Skeleton3D, semantic: String) -> int:
    var aliases: Array = ALIASES.get(semantic, [_normalize(semantic)])
    for i in range(skeleton.get_bone_count()):
        var normalized := _normalize(skeleton.get_bone_name(i))
        for alias in aliases:
            if normalized == String(alias):
                return i
    return -1

func _collect_skeletons(node: Node, result: Array[Skeleton3D]) -> void:
    if node is Skeleton3D:
        result.append(node as Skeleton3D)
    for child in node.get_children():
        _collect_skeletons(child, result)

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)

func _read_json(path: String) -> Variant:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return null
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    f.close()
    return parsed

func _v3(value: Variant) -> Vector3:
    if not value is Array or value.size() != 3:
        return Vector3(INF, INF, INF)
    return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _quat(value: Variant) -> Quaternion:
    if not value is Array or value.size() != 4:
        return Quaternion(INF, INF, INF, INF)
    return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

func _finite_v3(v: Vector3) -> bool:
    return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _finite_q(q: Quaternion) -> bool:
    return is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)

func _write_report(report: Dictionary) -> bool:
    var f := FileAccess.open(_report_path, FileAccess.WRITE)
    if f == null:
        return false
    f.store_string(JSON.stringify(report, "  "))
    f.close()
    return true

func _image_has_dynamic_range(image: Image) -> bool:
    var bytes := image.get_data()
    if bytes.is_empty():
        return false
    var stride: int = max(1, int(bytes.size() / 8192))
    var lo := 255
    var hi := 0
    var i := 0
    while i < bytes.size():
        var v: int = int(bytes[i])
        lo = min(lo, v)
        hi = max(hi, v)
        i += stride
    return hi - lo >= 16

func _run() -> void:
    var bundle = _read_json(_bundle_path)
    if not bundle is Dictionary:
        push_error("CIV1_SKELETON_WITNESS_FAIL: invalid bundle")
        quit(3)
        return
    if bundle.get("schema", "") != "grand-bruxelles-civ1-skeleton-witness-bundle-v1":
        push_error("CIV1_SKELETON_WITNESS_FAIL: schema")
        quit(4)
        return
    if bundle.get("diagnostic_only", false) is not bool or not bool(bundle["diagnostic_only"]):
        push_error("CIV1_SKELETON_WITNESS_FAIL: diagnostic rail")
        quit(5)
        return
    if bool(bundle.get("runtime_authorized", true)) or bool(bundle.get("visual_approval_claimed", true)) or bool(bundle.get("player_view_claimed", true)):
        push_error("CIV1_SKELETON_WITNESS_FAIL: production claim present")
        quit(6)
        return
    var frames = bundle.get("frames", [])
    var witness_frame := int(bundle.get("witness_frame", -1))
    if not frames is Array or frames.size() != 120 or witness_frame < 0 or witness_frame >= frames.size():
        push_error("CIV1_SKELETON_WITNESS_FAIL: frame contract")
        quit(7)
        return

    var packed := load(TARGET_SCENE) as PackedScene
    if packed == null:
        push_error("CIV1_SKELETON_WITNESS_FAIL: target load")
        quit(8)
        return
    var target := packed.instantiate()
    root.add_child(target)
    await process_frame

    var skeletons: Array[Skeleton3D] = []
    _collect_skeletons(target, skeletons)
    if skeletons.size() != 1:
        push_error("CIV1_SKELETON_WITNESS_FAIL: expected one Skeleton3D")
        quit(9)
        return
    var skeleton := skeletons[0]
    var mapping := {}
    for semantic in POSE_BONES:
        var idx := _bone_index(skeleton, semantic)
        if idx < 0:
            push_error("CIV1_SKELETON_WITNESS_FAIL: missing bone " + semantic)
            quit(10)
            return
        mapping[semantic] = idx

    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(target, meshes)
    if meshes.is_empty():
        push_error("CIV1_SKELETON_WITNESS_FAIL: no skinned mesh witness")
        quit(11)
        return
    var surface_count := 0
    var material_count := 0
    var skin_binding_count := 0
    for mi in meshes:
        if mi.mesh == null:
            continue
        surface_count += mi.mesh.get_surface_count()
        for s in range(mi.mesh.get_surface_count()):
            if mi.get_surface_override_material(s) != null or mi.mesh.surface_get_material(s) != null:
                material_count += 1
        if mi.get("skin") != null or not NodePath(mi.get("skeleton")).is_empty():
            skin_binding_count += 1
    if surface_count <= 0 or material_count <= 0 or skin_binding_count <= 0:
        push_error("CIV1_SKELETON_WITNESS_FAIL: mesh/skin/material integrity")
        quit(12)
        return

    var frame: Dictionary = frames[witness_frame]
    var poses: Dictionary = frame.get("poses", {})
    var expected := {}
    var min_world := Vector3(INF, INF, INF)
    var max_world := Vector3(-INF, -INF, -INF)
    for semantic in POSE_BONES:
        if not poses.has(semantic):
            push_error("CIV1_SKELETON_WITNESS_FAIL: missing pose " + semantic)
            quit(13)
            return
        var rec: Dictionary = poses[semantic]
        var origin := _v3(rec.get("origin", []))
        var rotation := _quat(rec.get("rotation_xyzw", []))
        if not _finite_v3(origin) or not _finite_q(rotation):
            push_error("CIV1_SKELETON_WITNESS_FAIL: non-finite pose")
            quit(14)
            return
        expected[semantic] = Transform3D(Basis(rotation), origin)

    # Apply parent-before-child global poses. This is ephemeral diagnostic state only.
    for semantic in POSE_BONES:
        skeleton.set_bone_global_pose(int(mapping[semantic]), expected[semantic])
    skeleton.force_update_all_bone_transforms()
    await process_frame

    var max_origin_error := 0.0
    var max_rotation_error_rad := 0.0
    for semantic in POSE_BONES:
        var actual := skeleton.get_bone_global_pose(int(mapping[semantic]))
        var wanted: Transform3D = expected[semantic]
        max_origin_error = max(max_origin_error, actual.origin.distance_to(wanted.origin))
        var aq := actual.basis.get_rotation_quaternion().normalized()
        var wq := wanted.basis.get_rotation_quaternion().normalized()
        var dot_abs: float = clampf(absf(aq.dot(wq)), 0.0, 1.0)
        max_rotation_error_rad = max(max_rotation_error_rad, 2.0 * acos(dot_abs))
        var wp := skeleton.to_global(actual.origin)
        min_world = Vector3(min(min_world.x, wp.x), min(min_world.y, wp.y), min(min_world.z, wp.z))
        max_world = Vector3(max(max_world.x, wp.x), max(max_world.y, wp.y), max(max_world.z, wp.z))
    if max_origin_error > 0.0001 or max_rotation_error_rad > 0.001:
        push_error("CIV1_SKELETON_WITNESS_FAIL: Godot pose application drift")
        quit(15)
        return

    var center := (min_world + max_world) * 0.5
    var extent := max_world - min_world
    var radius: float = maxf(0.75, maxf(extent.x, maxf(extent.y, extent.z)) * 0.75)

    var camera := Camera3D.new()
    root.add_child(camera)
    camera.fov = 50.0
    camera.position = center + Vector3(0.0, radius * 0.12, radius * 2.8)
    camera.look_at(center, Vector3.UP)
    camera.current = true

    var key := DirectionalLight3D.new()
    root.add_child(key)
    key.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
    key.light_energy = 1.5
    var fill := DirectionalLight3D.new()
    root.add_child(fill)
    fill.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
    fill.light_energy = 0.65

    var floor := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(radius * 4.0, radius * 4.0)
    floor.mesh = plane
    floor.position = Vector3(center.x, min_world.y - 0.01, center.z)
    var floor_mat := StandardMaterial3D.new()
    floor_mat.albedo_color = Color(0.22, 0.22, 0.24, 1.0)
    floor.material_override = floor_mat
    root.add_child(floor)

    root.size = Vector2i(WIDTH, HEIGHT)
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    if image == null or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        push_error("CIV1_SKELETON_WITNESS_FAIL: capture dimensions")
        quit(16)
        return
    if not _image_has_dynamic_range(image):
        push_error("CIV1_SKELETON_WITNESS_FAIL: blank/flat capture")
        quit(17)
        return
    if image.save_png(_png_path) != OK:
        push_error("CIV1_SKELETON_WITNESS_FAIL: png write")
        quit(18)
        return

    var report := {
        "schema": "grand-bruxelles-civ1-skeleton-witness-v1",
        "diagnostic_only": true,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
        "player_view_claimed": false,
        "resolution": [WIDTH, HEIGHT],
        "witness_frame": witness_frame,
        "pelvis_delta_mm": int(frame.get("pelvis_delta_mm", 0)),
        "mesh_instance_count": meshes.size(),
        "mesh_surface_count": surface_count,
        "material_surface_count": material_count,
        "skin_binding_count": skin_binding_count,
        "skeleton_bone_count": skeleton.get_bone_count(),
        "max_global_pose_origin_error_m": max_origin_error,
        "max_global_pose_rotation_error_rad": max_rotation_error_rad,
        "capture_nonflat": true,
        "verdict": "REQUIRE_HUMAN_VISUAL_REVIEW",
    }
    if not _write_report(report):
        push_error("CIV1_SKELETON_WITNESS_FAIL: report write")
        quit(19)
        return
    print(
        "CIV1_SKELETON_WITNESS_OK frame=%d origin_error=%.9f rotation_error=%.9f meshes=%d materials=%d" % [
            witness_frame, max_origin_error, max_rotation_error_rad, meshes.size(), material_count
        ]
    )
    quit(0)
