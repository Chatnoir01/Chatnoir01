extends SceneTree

const REVIEW_ROOT := "res://assets/characters/_review/rocketbox_midi_v1"
const PROFILES := [
    {"id": "Female_Adult_01", "role": "civilian", "x": -2.15},
    {"id": "Male_Adult_01", "role": "civilian", "x": 0.0},
    {"id": "Police_Female_01", "role": "police", "x": 2.15},
]
const TARGET_HEIGHT_M := 1.75

var _metrics: Dictionary = {
    "schema": "grand-bruxelles-authored-npc-candidate-witness-v1",
    "production_authorized": false,
    "profiles": [],
}

func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var output := "/tmp/midi-realistic-authored-npcs-candidate.png"
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        output = str(args[0])

    var world := Node3D.new()
    world.name = "AuthoredNpcCandidateWitness"
    get_root().add_child(world)

    _build_floor(world)
    _build_lighting(world)

    for profile in PROFILES:
        var result := _spawn_profile(world, profile)
        if not bool(result.get("ok", false)):
            push_error("MIDI_REALISTIC_AUTHORED_NPC_CANDIDATE_FAIL: %s" % str(result.get("error", "unknown")))
            quit(2)
            return
        _metrics["profiles"].append(result.get("metrics", {}))

    var camera := Camera3D.new()
    camera.name = "PlayerHeightReviewCamera"
    camera.position = Vector3(0.0, 1.62, 7.25)
    world.add_child(camera)
    camera.look_at(Vector3(0.0, 1.10, 0.0), Vector3.UP)
    camera.current = true

    for _frame in range(12):
        await process_frame
        await RenderingServer.frame_post_draw

    var image := get_root().get_texture().get_image()
    if image == null or image.is_empty():
        push_error("MIDI_REALISTIC_AUTHORED_NPC_CANDIDATE_FAIL: viewport image unavailable")
        quit(2)
        return
    var err := image.save_png(output)
    if err != OK:
        push_error("MIDI_REALISTIC_AUTHORED_NPC_CANDIDATE_FAIL: could not save PNG: %s" % error_string(err))
        quit(2)
        return

    var metrics_path := output.get_basename() + ".metrics.json"
    var metrics_file := FileAccess.open(metrics_path, FileAccess.WRITE)
    if metrics_file == null:
        push_error("MIDI_REALISTIC_AUTHORED_NPC_CANDIDATE_FAIL: could not save metrics")
        quit(2)
        return
    metrics_file.store_string(JSON.stringify(_metrics, "  ") + "\n")
    metrics_file.close()

    print("MIDI_REALISTIC_AUTHORED_NPC_CANDIDATE_OK: %s" % output)
    quit(0)


func _build_floor(parent: Node3D) -> void:
    var floor := MeshInstance3D.new()
    floor.name = "NeutralReviewGround"
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(12.0, 8.0)
    floor.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.34, 0.35, 0.37)
    mat.roughness = 0.92
    floor.material_override = mat
    parent.add_child(floor)


func _build_lighting(parent: Node3D) -> void:
    var key := DirectionalLight3D.new()
    key.name = "KeyLight"
    key.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
    key.light_energy = 1.35
    key.shadow_enabled = true
    parent.add_child(key)

    var fill := OmniLight3D.new()
    fill.name = "FillLight"
    fill.position = Vector3(-3.5, 3.5, 4.0)
    fill.light_energy = 4.5
    fill.omni_range = 10.0
    parent.add_child(fill)

    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.15, 0.17, 0.20)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.72, 0.76, 0.82)
    env.ambient_light_energy = 0.58
    environment.environment = env
    parent.add_child(environment)


func _spawn_profile(parent: Node3D, profile: Dictionary) -> Dictionary:
    var profile_id := str(profile.get("id", ""))
    var resource_path := "%s/%s/Export/%s.fbx" % [REVIEW_ROOT, profile_id, profile_id]
    if not ResourceLoader.exists(resource_path):
        return {"ok": false, "error": "resource missing after intake/import: %s" % resource_path}

    var packed := ResourceLoader.load(resource_path) as PackedScene
    if packed == null:
        return {"ok": false, "error": "resource is not a PackedScene: %s" % resource_path}

    var instance := packed.instantiate() as Node3D
    if instance == null:
        return {"ok": false, "error": "could not instantiate: %s" % resource_path}
    instance.name = "Candidate_%s" % profile_id
    parent.add_child(instance)

    var bounds := _bounds_in_root_space(instance)
    if bounds.size.y <= 0.01:
        instance.queue_free()
        return {"ok": false, "error": "invalid mesh bounds for %s: %s" % [profile_id, str(bounds)]}

    var uniform_scale := TARGET_HEIGHT_M / bounds.size.y
    if uniform_scale < 0.001 or uniform_scale > 100.0:
        instance.queue_free()
        return {"ok": false, "error": "implausible normalization scale for %s: %.6f" % [profile_id, uniform_scale]}

    instance.scale = Vector3.ONE * uniform_scale
    instance.position = Vector3(float(profile.get("x", 0.0)), -bounds.position.y * uniform_scale, 0.0)

    var mesh_count := _count_type(instance, "MeshInstance3D")
    var skeleton_count := _count_type(instance, "Skeleton3D")
    if mesh_count <= 0 or skeleton_count <= 0:
        instance.queue_free()
        return {"ok": false, "error": "%s lacks authored mesh/skeleton (meshes=%d skeletons=%d)" % [profile_id, mesh_count, skeleton_count]}

    var label := Label3D.new()
    label.text = "%s\n%s" % [profile_id, str(profile.get("role", ""))]
    label.font_size = 30
    label.position = Vector3(0.0, 2.12 / uniform_scale, 0.0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = true
    instance.add_child(label)

    return {
        "ok": true,
        "metrics": {
            "id": profile_id,
            "role": str(profile.get("role", "")),
            "resource": resource_path,
            "raw_height": bounds.size.y,
            "normalization_scale": uniform_scale,
            "target_height_m": TARGET_HEIGHT_M,
            "mesh_count": mesh_count,
            "skeleton_count": skeleton_count,
        }
    }


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
            Vector3(local.position.x, local.position.y, local.position.z),
            Vector3(local.end.x, local.position.y, local.position.z),
            Vector3(local.position.x, local.end.y, local.position.z),
            Vector3(local.end.x, local.end.y, local.position.z),
            Vector3(local.position.x, local.position.y, local.end.z),
            Vector3(local.end.x, local.position.y, local.end.z),
            Vector3(local.position.x, local.end.y, local.end.z),
            Vector3(local.end.x, local.end.y, local.end.z),
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
    var count := 0
    if node.get_class() == type_name:
        count += 1
    for child in node.get_children():
        count += _count_type(child, type_name)
    return count
