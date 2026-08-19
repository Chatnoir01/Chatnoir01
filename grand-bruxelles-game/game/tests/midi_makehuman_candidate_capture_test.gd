extends SceneTree

const RESOURCE_PATH := "res://assets/characters/_review/makehuman_midi_v1/FemalePilot/FemalePilot.fbx"
const TARGET_HEIGHT_M := 1.72
const WITNESS_SIZE := Vector2i(1280, 720)

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var output := "/tmp/midi-makehuman-candidate.png"
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        output = str(args[0])

    if not ResourceLoader.exists(RESOURCE_PATH):
        _fail("candidate resource missing after MakeHuman export/import: %s" % RESOURCE_PATH)
        return
    var packed := ResourceLoader.load(RESOURCE_PATH) as PackedScene
    if packed == null:
        _fail("candidate resource is not a PackedScene")
        return
    var person := packed.instantiate() as Node3D
    if person == null:
        _fail("candidate could not instantiate")
        return

    var viewport := SubViewport.new()
    viewport.name = "IsolatedNpcReviewViewport"
    viewport.size = WITNESS_SIZE
    viewport.own_world_3d = true
    viewport.transparent_bg = false
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.msaa_3d = Viewport.MSAA_4X
    get_root().add_child(viewport)

    var world := Node3D.new()
    world.name = "MakeHumanCandidateWitness"
    viewport.add_child(world)
    world.add_child(person)

    var bounds := _bounds_in_root_space(person)
    if bounds.size.y <= 0.01:
        _fail("candidate mesh bounds invalid: %s" % str(bounds))
        return
    var scale_factor := TARGET_HEIGHT_M / bounds.size.y
    if scale_factor < 0.001 or scale_factor > 100.0:
        _fail("candidate normalization scale implausible: %.6f" % scale_factor)
        return
    person.scale = Vector3.ONE * scale_factor
    person.position.y = -bounds.position.y * scale_factor

    var mesh_count := _count_type(person, "MeshInstance3D")
    var skeleton := _find_first_skeleton(person)
    if mesh_count <= 0:
        _fail("candidate has no MeshInstance3D")
        return
    if skeleton == null:
        _fail("candidate has no Skeleton3D")
        return

    var bone_names: Array[String] = []
    for bone_index in range(skeleton.get_bone_count()):
        bone_names.append(skeleton.get_bone_name(bone_index))
    var relaxed_pose_bones := _apply_relaxed_review_pose(skeleton)
    var material_stats := _material_stats(person)
    if int(material_stats.get("textured_surfaces", 0)) < 4:
        _fail("candidate must import at least four textured surfaces for a useful fidelity review: %s" % str(material_stats))
        return

    _build_floor(world)
    _build_lighting(world)

    var camera := Camera3D.new()
    camera.name = "PlayerDistanceCamera"
    camera.position = Vector3(0.0, 1.48, 3.20)
    camera.fov = 43.0
    camera.near = 0.05
    world.add_child(camera)
    camera.look_at(Vector3(0.0, 0.93, 0.0), Vector3.UP)
    camera.current = true

    if not await _save_after_frames(viewport, output, 18):
        _fail("could not save full-body PNG")
        return

    camera.position = Vector3(0.0, 1.46, 1.48)
    camera.fov = 39.0
    camera.look_at(Vector3(0.0, 1.40, 0.0), Vector3.UP)
    var close_output := output.get_basename() + "_close.png"
    if not await _save_after_frames(viewport, close_output, 10):
        _fail("could not save close PNG")
        return

    var metrics := {
        "schema": "grand-bruxelles-makehuman-candidate-witness-v8",
        "production_authorized": false,
        "diagnostic_mode": "art_v2_binary_fbx_patched_normal_indices",
        "pose_mode": "distributed_shoulder_upperarm_review_pose",
        "lighting_mode": "neutral_low_energy_review",
        "resource": RESOURCE_PATH,
        "target_height_m": TARGET_HEIGHT_M,
        "raw_height": bounds.size.y,
        "normalization_scale": scale_factor,
        "mesh_count": mesh_count,
        "skeleton_count": 1,
        "skeleton_bones": skeleton.get_bone_count(),
        "bone_names": bone_names,
        "relaxed_review_pose_bones": relaxed_pose_bones,
        "materials": material_stats,
        "full_camera_distance_m": Vector3(0.0, 1.48, 3.20).distance_to(Vector3(0.0, 0.93, 0.0)),
        "close_camera_distance_m": camera.position.distance_to(Vector3(0.0, 1.40, 0.0)),
        "resolution": [WITNESS_SIZE.x, WITNESS_SIZE.y],
        "isolated_subviewport": true,
        "full_png": output,
        "close_png": close_output
    }
    var metrics_file := FileAccess.open(output.get_basename() + ".metrics.json", FileAccess.WRITE)
    if metrics_file == null:
        _fail("could not save metrics")
        return
    metrics_file.store_string(JSON.stringify(metrics, "  ") + "\n")
    metrics_file.close()

    print("MIDI_MAKEHUMAN_CANDIDATE_OK: %s close=%s meshes=%d skeleton_bones=%d textured_surfaces=%d" % [output, close_output, mesh_count, skeleton.get_bone_count(), int(material_stats.get("textured_surfaces", 0))])
    quit(0)

func _save_after_frames(viewport: SubViewport, path: String, frame_count: int) -> bool:
    for _frame in range(frame_count):
        await process_frame
        await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return false
    return image.save_png(path) == OK

func _apply_relaxed_review_pose(skeleton: Skeleton3D) -> Array[String]:
    # Keep the same total arm drop as run #38, but distribute it across the
    # shoulder and upper-arm joints so the witness does not create a hard,
    # artificial shoulder corner. Review-only; production uses authored motion.
    var applied: Array[String] = []
    var left_shoulder := skeleton.find_bone("shoulder01.L")
    var right_shoulder := skeleton.find_bone("shoulder01.R")
    var left_upperarm := skeleton.find_bone("upperarm01.L")
    var right_upperarm := skeleton.find_bone("upperarm01.R")
    var z_axis := Vector3(0.0, 0.0, 1.0)
    if left_shoulder >= 0:
        skeleton.set_bone_pose_rotation(left_shoulder, Quaternion(z_axis, deg_to_rad(-15.0)))
        applied.append("shoulder01.L")
    if right_shoulder >= 0:
        skeleton.set_bone_pose_rotation(right_shoulder, Quaternion(z_axis, deg_to_rad(15.0)))
        applied.append("shoulder01.R")
    if left_upperarm >= 0:
        skeleton.set_bone_pose_rotation(left_upperarm, Quaternion(z_axis, deg_to_rad(-53.0)))
        applied.append("upperarm01.L")
    if right_upperarm >= 0:
        skeleton.set_bone_pose_rotation(right_upperarm, Quaternion(z_axis, deg_to_rad(53.0)))
        applied.append("upperarm01.R")
    return applied

func _material_stats(root: Node) -> Dictionary:
    var surfaces := 0
    var material_surfaces := 0
    var textured_surfaces := 0
    var normal_mapped_surfaces := 0
    var material_names: Array[String] = []
    var material_classes: Array[String] = []
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if mesh_node.mesh == null:
            continue
        for surface_index in range(mesh_node.mesh.get_surface_count()):
            surfaces += 1
            var mat := mesh_node.get_active_material(surface_index)
            if mat == null:
                continue
            material_surfaces += 1
            material_names.append(str(mat.resource_name))
            material_classes.append(str(mat.get_class()))
            if mat is BaseMaterial3D:
                var base := mat as BaseMaterial3D
                if base.albedo_texture != null:
                    textured_surfaces += 1
                if base.normal_enabled and base.normal_texture != null:
                    normal_mapped_surfaces += 1
    return {
        "surfaces": surfaces,
        "material_surfaces": material_surfaces,
        "textured_surfaces": textured_surfaces,
        "normal_mapped_surfaces": normal_mapped_surfaces,
        "material_names": material_names,
        "material_classes": material_classes
    }

func _build_floor(parent: Node3D) -> void:
    var floor := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(7.0, 7.0)
    floor.mesh = plane
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.31, 0.32, 0.34)
    mat.roughness = 0.92
    floor.material_override = mat
    parent.add_child(floor)

func _build_lighting(parent: Node3D) -> void:
    # Run #35 proved the old 1.05 + 2.5 + 0.42 light rig burned out skin detail.
    # Use a neutral, lower-energy review setup so albedo/face quality is judgeable.
    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-48.0, -24.0, 0.0)
    key.light_energy = 0.62
    key.shadow_enabled = true
    parent.add_child(key)
    var fill := OmniLight3D.new()
    fill.position = Vector3(-2.2, 3.0, 2.5)
    fill.light_energy = 0.85
    fill.omni_range = 8.0
    parent.add_child(fill)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.10, 0.115, 0.14)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.66, 0.70, 0.76)
    env.ambient_light_energy = 0.20
    environment.environment = env
    parent.add_child(environment)

func _bounds_in_root_space(root: Node3D) -> AABB:
    var found := false
    var merged := AABB()
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if mesh_node.mesh == null:
            continue
        var local := mesh_node.get_aabb()
        var corners := [
            Vector3(local.position.x, local.position.y, local.position.z), Vector3(local.end.x, local.position.y, local.position.z),
            Vector3(local.position.x, local.end.y, local.position.z), Vector3(local.end.x, local.end.y, local.position.z),
            Vector3(local.position.x, local.position.y, local.end.z), Vector3(local.end.x, local.position.y, local.end.z),
            Vector3(local.position.x, local.end.y, local.end.z), Vector3(local.end.x, local.end.y, local.end.z),
        ]
        for corner in corners:
            var point := root.to_local(mesh_node.to_global(corner))
            if not found:
                merged = AABB(point, Vector3.ZERO)
                found = true
            else:
                merged = merged.expand(point)
    return merged

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        out.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, out)

func _find_first_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_first_skeleton(child)
        if found != null:
            return found
    return null

func _count_type(node: Node, type_name: String) -> int:
    var count := 1 if node.get_class() == type_name else 0
    for child in node.get_children():
        count += _count_type(child, type_name)
    return count

func _fail(message: String) -> void:
    push_error("MIDI_MAKEHUMAN_CANDIDATE_FAIL: %s" % message)
    quit(2)
