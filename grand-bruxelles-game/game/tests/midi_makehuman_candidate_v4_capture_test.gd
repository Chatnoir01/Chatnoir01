extends SceneTree

const RESOURCE_PATH := "res://assets/characters/_review/makehuman_midi_v4/FemalePilot/FemalePilot.fbx"
const REVIEW_TEXTURE_ROOT := "res://assets/characters/_review/makehuman_midi_v4/FemalePilot/textures/"
const TARGET_HEIGHT_M := 1.72
const WITNESS_SIZE := Vector2i(1280, 720)
const REQUIRED_NORMAL_MAPS := {
    "cargo_pants": "cargo_pants_norm.png",
    "shoes04": "shoes04_normal.png",
}

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var output := "/tmp/midi-makehuman-v4-candidate.png"
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
    viewport.name = "IsolatedNpcV4ReviewViewport"
    viewport.size = WITNESS_SIZE
    viewport.own_world_3d = true
    viewport.transparent_bg = false
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.msaa_3d = Viewport.MSAA_4X
    get_root().add_child(viewport)

    var world := Node3D.new()
    world.name = "MakeHumanV4CandidateWitness"
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

    # The MakeHuman export already ships authored normal textures for cargo trousers
    # and shoes, but the FBX import observed in V3 left them disconnected. Bind only
    # those source-provided maps in this review witness; no synthetic normal maps and
    # no production material mutation are allowed here.
    var sourced_normal_maps := _apply_sourced_normal_maps(person)
    if int(sourced_normal_maps.get("mapped_surfaces", 0)) != REQUIRED_NORMAL_MAPS.size():
        _fail("required sourced normal maps were not bound: %s" % str(sourced_normal_maps))
        return

    var material_stats := _material_stats(person)
    if int(material_stats.get("textured_surfaces", 0)) < 4:
        _fail("candidate must import at least four textured surfaces: %s" % str(material_stats))
        return
    if int(material_stats.get("normal_mapped_surfaces", 0)) < REQUIRED_NORMAL_MAPS.size():
        _fail("candidate lost source-provided normal maps after binding: %s" % str(material_stats))
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

    camera.position = Vector3(1.95, 1.52, 2.05)
    camera.fov = 43.0
    camera.look_at(Vector3(0.0, 1.03, 0.0), Vector3.UP)
    var side_output := output.get_basename() + "_three_quarter.png"
    if not await _save_after_frames(viewport, side_output, 10):
        _fail("could not save three-quarter PNG")
        return

    var metrics := {
        "schema": "grand-bruxelles-makehuman-candidate-witness-v11",
        "production_authorized": false,
        "diagnostic_mode": "art_v4_natural_skin_face_clear_casual_binary_fbx_sourced_normals",
        "pose_mode": "upperarm_relaxed_62deg_no_shoulder_override",
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
        "sourced_normal_maps": sourced_normal_maps,
        "full_camera_distance_m": Vector3(0.0, 1.48, 3.20).distance_to(Vector3(0.0, 0.93, 0.0)),
        "close_camera_distance_m": Vector3(0.0, 1.46, 1.48).distance_to(Vector3(0.0, 1.40, 0.0)),
        "three_quarter_camera_distance_m": camera.position.distance_to(Vector3(0.0, 1.03, 0.0)),
        "resolution": [WITNESS_SIZE.x, WITNESS_SIZE.y],
        "isolated_subviewport": true,
        "full_png": output,
        "close_png": close_output,
        "three_quarter_png": side_output
    }
    var metrics_file := FileAccess.open(output.get_basename() + ".metrics.json", FileAccess.WRITE)
    if metrics_file == null:
        _fail("could not save metrics")
        return
    metrics_file.store_string(JSON.stringify(metrics, "  ") + "\n")
    metrics_file.close()

    print("MIDI_MAKEHUMAN_V4_CANDIDATE_OK: %s close=%s three_quarter=%s meshes=%d skeleton_bones=%d textured_surfaces=%d normal_mapped_surfaces=%d" % [output, close_output, side_output, mesh_count, skeleton.get_bone_count(), int(material_stats.get("textured_surfaces", 0)), int(material_stats.get("normal_mapped_surfaces", 0))])
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
    # V3 distributed the arm drop across shoulder + upper-arm and visibly left the
    # arms too far from the torso. V4 deliberately removes shoulder overrides and
    # uses a milder upper-arm-only relaxation than V2's 68 degrees. Review-only.
    var applied: Array[String] = []
    var left := skeleton.find_bone("upperarm01.L")
    var right := skeleton.find_bone("upperarm01.R")
    var z_axis := Vector3(0.0, 0.0, 1.0)
    if left >= 0:
        skeleton.set_bone_pose_rotation(left, Quaternion(z_axis, deg_to_rad(-62.0)))
        applied.append("upperarm01.L")
    if right >= 0:
        skeleton.set_bone_pose_rotation(right, Quaternion(z_axis, deg_to_rad(62.0)))
        applied.append("upperarm01.R")
    return applied

func _apply_sourced_normal_maps(root: Node) -> Dictionary:
    var textures: Dictionary = {}
    var missing_paths: Array[String] = []
    for material_name: String in REQUIRED_NORMAL_MAPS.keys():
        var path := REVIEW_TEXTURE_ROOT + str(REQUIRED_NORMAL_MAPS[material_name])
        if not ResourceLoader.exists(path):
            missing_paths.append(path)
            continue
        var texture := ResourceLoader.load(path) as Texture2D
        if texture == null:
            missing_paths.append(path)
            continue
        textures[material_name] = texture

    var mapped_surfaces := 0
    var mapped_materials: Array[String] = []
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if mesh_node.mesh == null:
            continue
        for surface_index in range(mesh_node.mesh.get_surface_count()):
            var mat := mesh_node.get_active_material(surface_index)
            if not (mat is BaseMaterial3D):
                continue
            var base := mat as BaseMaterial3D
            var material_name := str(base.resource_name)
            if not textures.has(material_name):
                continue
            var review_material := base.duplicate() as BaseMaterial3D
            if review_material == null:
                continue
            review_material.normal_enabled = true
            review_material.normal_texture = textures[material_name] as Texture2D
            review_material.normal_scale = 1.0
            mesh_node.set_surface_override_material(surface_index, review_material)
            mapped_surfaces += 1
            mapped_materials.append(material_name)

    return {
        "source_only": true,
        "mapped_surfaces": mapped_surfaces,
        "mapped_materials": mapped_materials,
        "missing_paths": missing_paths,
        "expected_materials": REQUIRED_NORMAL_MAPS.keys(),
    }

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
    push_error("MIDI_MAKEHUMAN_V4_CANDIDATE_FAIL: %s" % message)
    quit(2)
