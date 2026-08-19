extends SceneTree

const RESOURCE_PATH := "res://assets/characters/_review/makehuman_midi_v1/FemalePilot/FemalePilot.fbx"
const TARGET_HEIGHT_M := 1.72

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

    var world := Node3D.new()
    world.name = "MakeHumanCandidateWitness"
    get_root().add_child(world)
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
    var skeleton_count := _count_type(person, "Skeleton3D")
    if mesh_count <= 0:
        _fail("candidate has no MeshInstance3D")
        return
    if skeleton_count <= 0:
        _fail("candidate has no Skeleton3D")
        return

    _build_floor(world)
    _build_lighting(world)

    var camera := Camera3D.new()
    camera.name = "PlayerDistanceCamera"
    camera.position = Vector3(0.0, 1.48, 3.25)
    camera.fov = 43.0
    world.add_child(camera)
    camera.look_at(Vector3(0.0, 0.93, 0.0), Vector3.UP)
    camera.current = true

    for _frame in range(16):
        await process_frame
        await RenderingServer.frame_post_draw

    var image := get_root().get_texture().get_image()
    if image == null or image.is_empty():
        _fail("viewport image unavailable")
        return
    if image.save_png(output) != OK:
        _fail("could not save PNG")
        return

    var metrics := {
        "schema": "grand-bruxelles-makehuman-candidate-witness-v1",
        "production_authorized": false,
        "resource": RESOURCE_PATH,
        "target_height_m": TARGET_HEIGHT_M,
        "raw_height": bounds.size.y,
        "normalization_scale": scale_factor,
        "mesh_count": mesh_count,
        "skeleton_count": skeleton_count,
        "camera_distance_m": camera.position.distance_to(Vector3(0.0, 0.93, 0.0)),
        "resolution": [image.get_width(), image.get_height()]
    }
    var metrics_file := FileAccess.open(output.get_basename() + ".metrics.json", FileAccess.WRITE)
    if metrics_file == null:
        _fail("could not save metrics")
        return
    metrics_file.store_string(JSON.stringify(metrics, "  ") + "\n")
    metrics_file.close()

    print("MIDI_MAKEHUMAN_CANDIDATE_OK: %s meshes=%d skeletons=%d" % [output, mesh_count, skeleton_count])
    quit(0)

func _build_floor(parent: Node3D) -> void:
    var floor := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(7.0, 7.0)
    floor.mesh = plane
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.34, 0.35, 0.37)
    mat.roughness = 0.92
    floor.material_override = mat
    parent.add_child(floor)

func _build_lighting(parent: Node3D) -> void:
    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-48.0, -24.0, 0.0)
    key.light_energy = 1.3
    key.shadow_enabled = true
    parent.add_child(key)
    var fill := OmniLight3D.new()
    fill.position = Vector3(-2.2, 3.0, 2.5)
    fill.light_energy = 3.6
    fill.omni_range = 8.0
    parent.add_child(fill)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.13, 0.15, 0.18)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.72, 0.76, 0.82)
    env.ambient_light_energy = 0.55
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

func _count_type(node: Node, type_name: String) -> int:
    var count := 1 if node.get_class() == type_name else 0
    for child in node.get_children():
        count += _count_type(child, type_name)
    return count

func _fail(message: String) -> void:
    push_error("MIDI_MAKEHUMAN_CANDIDATE_FAIL: %s" % message)
    quit(2)
