extends SceneTree

const RESOURCE_PATH := "res://assets/characters/_review/mpfb_midi_v1/FemalePilot/FemalePilot.glb"
const BONE_MAP_PATH := "res://data/qa/midi_makehuman_humanoid_bone_map.json"
const TARGET_HEIGHT_M := 1.72
const WITNESS_SIZE := Vector2i(1280, 720)
const MIN_TEXTURED_SURFACES := 6
const MIN_NORMAL_MAPPED_SURFACES := 2

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var output := "/tmp/midi-mpfb-high-fidelity-candidate.png"
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        output = str(args[0])

    if not ResourceLoader.exists(RESOURCE_PATH):
        _fail("MPFB GLB candidate missing: %s" % RESOURCE_PATH)
        return
    var packed := ResourceLoader.load(RESOURCE_PATH) as PackedScene
    if packed == null:
        _fail("MPFB GLB did not import as PackedScene")
        return
    var person := packed.instantiate() as Node3D
    if person == null:
        _fail("MPFB GLB could not instantiate")
        return

    var viewport := SubViewport.new()
    viewport.name = "MPFBHighFidelityReviewViewport"
    viewport.size = WITNESS_SIZE
    viewport.own_world_3d = true
    viewport.transparent_bg = false
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.msaa_3d = Viewport.MSAA_4X
    get_root().add_child(viewport)

    var world := Node3D.new()
    world.name = "MPFBHighFidelityCandidateWitness"
    viewport.add_child(world)
    world.add_child(person)

    var bounds := _bounds_in_root_space(person)
    if bounds.size.y <= 0.01:
        _fail("MPFB candidate mesh bounds invalid: %s" % str(bounds))
        return
    var scale_factor := TARGET_HEIGHT_M / bounds.size.y
    if scale_factor < 0.5 or scale_factor > 2.0:
        _fail("MPFB metre-scale normalization is implausible: raw_height=%.5f scale=%.5f" % [bounds.size.y, scale_factor])
        return
    person.scale = Vector3.ONE * scale_factor
    person.position.y = -bounds.position.y * scale_factor

    var skeleton := _find_first_skeleton(person)
    if skeleton == null:
        _fail("MPFB candidate has no Skeleton3D")
        return
    var retarget := _build_retarget_readiness(skeleton)
    if not bool(retarget.get("ready", false)):
        _fail("MPFB candidate lost V4 humanoid retarget readiness: %s" % str(retarget))
        return

    var relaxed_pose_bones := _apply_v4_control_pose(skeleton)
    if relaxed_pose_bones.size() != 2:
        _fail("MPFB candidate cannot reproduce V4 control pose")
        return

    var materials := _material_stats(person)
    if int(materials.get("textured_surfaces", 0)) < MIN_TEXTURED_SURFACES:
        _fail("MPFB GameEngine GLB lost too many textured surfaces: %s" % str(materials))
        return
    if int(materials.get("normal_mapped_surfaces", 0)) < MIN_NORMAL_MAPPED_SURFACES:
        _fail("MPFB GameEngine GLB regressed below V4 normal-map floor: %s" % str(materials))
        return

    var triangle_count := _triangle_count(person)
    if triangle_count <= 0:
        _fail("MPFB candidate triangle count invalid")
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
        _fail("could not save MPFB full-body PNG")
        return

    camera.position = Vector3(0.0, 1.46, 1.48)
    camera.fov = 39.0
    camera.look_at(Vector3(0.0, 1.40, 0.0), Vector3.UP)
    var close_output := output.get_basename() + "_close.png"
    if not await _save_after_frames(viewport, close_output, 10):
        _fail("could not save MPFB close PNG")
        return

    camera.position = Vector3(1.95, 1.52, 2.05)
    camera.fov = 43.0
    camera.look_at(Vector3(0.0, 1.03, 0.0), Vector3.UP)
    var side_output := output.get_basename() + "_three_quarter.png"
    if not await _save_after_frames(viewport, side_output, 10):
        _fail("could not save MPFB three-quarter PNG")
        return

    var metrics := {
        "schema": "grand-bruxelles-mpfb-godot-fidelity-witness-v1",
        "production_authorized": false,
        "candidate": "mpfb_2_0_17_gameengine_glb",
        "control": "makehuman_v4_same_mhm_identity_same_camera",
        "resource": RESOURCE_PATH,
        "target_height_m": TARGET_HEIGHT_M,
        "raw_height_m": bounds.size.y,
        "normalization_scale": scale_factor,
        "skeleton_bones": skeleton.get_bone_count(),
        "retarget_readiness": retarget,
        "control_pose_bones": relaxed_pose_bones,
        "materials": materials,
        "triangle_count": triangle_count,
        "resolution": [WITNESS_SIZE.x, WITNESS_SIZE.y],
        "full_png": output,
        "close_png": close_output,
        "three_quarter_png": side_output,
        "isolated_subviewport": true
    }
    var metrics_file := FileAccess.open(output.get_basename() + ".metrics.json", FileAccess.WRITE)
    if metrics_file == null:
        _fail("could not save MPFB witness metrics")
        return
    metrics_file.store_string(JSON.stringify(metrics, "  ") + "\n")
    metrics_file.close()

    print("MIDI_MPFB_HIGH_FIDELITY_OK full=%s close=%s three_quarter=%s triangles=%d bones=%d textured=%d normals=%d production_authorized=false" % [
        output,
        close_output,
        side_output,
        triangle_count,
        skeleton.get_bone_count(),
        int(materials.get("textured_surfaces", 0)),
        int(materials.get("normal_mapped_surfaces", 0))
    ])
    quit(0)

func _build_retarget_readiness(skeleton: Skeleton3D) -> Dictionary:
    var config := _read_json(BONE_MAP_PATH)
    var mapping_variant: Variant = config.get("required_core_mapping", {})
    var expectations_variant: Variant = config.get("required_profile_parent_expectations", {})
    if not mapping_variant is Dictionary or not expectations_variant is Dictionary:
        return {"ready": false, "reason": "bone_map_config_invalid"}
    var mapping := mapping_variant as Dictionary
    var expectations := expectations_variant as Dictionary
    var profile := SkeletonProfileHumanoid.new()
    var bone_map := BoneMap.new()
    bone_map.profile = profile
    var source_to_profile: Dictionary = {}
    var failures: Array[String] = []

    for profile_key: Variant in mapping.keys():
        var profile_name := str(profile_key)
        var source_name := str(mapping[profile_key])
        if profile.find_bone(StringName(profile_name)) < 0:
            failures.append("profile_missing:%s" % profile_name)
            continue
        if skeleton.find_bone(source_name) < 0:
            failures.append("source_missing:%s" % source_name)
            continue
        bone_map.set_skeleton_bone_name(StringName(profile_name), StringName(source_name))
        if str(bone_map.get_skeleton_bone_name(StringName(profile_name))) != source_name:
            failures.append("roundtrip:%s" % profile_name)
            continue
        source_to_profile[source_name] = profile_name

    for child_key: Variant in expectations.keys():
        var child_profile := str(child_key)
        var expected_parent := str(expectations[child_key])
        if not mapping.has(child_profile):
            failures.append("mapping_missing:%s" % child_profile)
            continue
        var child_index := skeleton.find_bone(str(mapping[child_profile]))
        if child_index < 0:
            continue
        var parent_index := skeleton.get_bone_parent(child_index)
        var nearest := ""
        while parent_index >= 0:
            var parent_name := skeleton.get_bone_name(parent_index)
            if source_to_profile.has(parent_name):
                nearest = str(source_to_profile[parent_name])
                break
            parent_index = skeleton.get_bone_parent(parent_index)
        if nearest != expected_parent:
            failures.append("parent:%s=%s expected=%s" % [child_profile, nearest, expected_parent])

    return {
        "ready": failures.is_empty() and source_to_profile.size() == mapping.size(),
        "mapped_core_count": source_to_profile.size(),
        "required_core_count": mapping.size(),
        "failures": failures,
        "hips_source_bone": str(mapping.get("Hips", "")),
        "root_motion_policy": str(config.get("root_motion_policy", ""))
    }

func _apply_v4_control_pose(skeleton: Skeleton3D) -> Array[String]:
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

func _material_stats(root: Node) -> Dictionary:
    var surfaces := 0
    var textured_surfaces := 0
    var normal_mapped_surfaces := 0
    var material_names: Array[String] = []
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
            material_names.append(str(mat.resource_name))
            if mat is BaseMaterial3D:
                var base := mat as BaseMaterial3D
                if base.albedo_texture != null:
                    textured_surfaces += 1
                if base.normal_enabled and base.normal_texture != null:
                    normal_mapped_surfaces += 1
    return {
        "surfaces": surfaces,
        "textured_surfaces": textured_surfaces,
        "normal_mapped_surfaces": normal_mapped_surfaces,
        "material_names": material_names
    }

func _triangle_count(root: Node) -> int:
    var total := 0
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if mesh_node.mesh == null:
            continue
        for surface_index in range(mesh_node.mesh.get_surface_count()):
            var arrays := mesh_node.mesh.surface_get_arrays(surface_index)
            if arrays.is_empty():
                continue
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            if not indices.is_empty():
                total += indices.size() / 3
            else:
                var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                total += vertices.size() / 3
    return total

func _save_after_frames(viewport: SubViewport, path: String, frame_count: int) -> bool:
    for _frame in range(frame_count):
        await process_frame
        await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return false
    return image.save_png(path) == OK

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

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}

func _fail(message: String) -> void:
    push_error("MIDI_MPFB_HIGH_FIDELITY_FAIL: %s" % message)
    quit(2)
