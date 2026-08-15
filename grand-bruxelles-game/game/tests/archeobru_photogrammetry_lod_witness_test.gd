extends SceneTree

const ASSET_DIR := "res://artifacts/ci_photogrammetry"
const OUTPUT_DIR := "res://artifacts/visual/archeobru_photogrammetry"
const ASSETS := {
    "source": ASSET_DIR + "/source.glb",
    "quality": ASSET_DIR + "/lod_quality.glb",
    "web": ASSET_DIR + "/lod_web.glb",
}
const VIEW_ANGLES := [0.0, 0.65, -0.65]
const TARGET_HEIGHT_M := 12.0

var _failed := false

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    for label: String in ASSETS.keys():
        var path := str(ASSETS[label])
        if not ResourceLoader.exists(path):
            _fail("missing imported GLB: %s" % path)
            return
        if not await _render_asset(label, path):
            return
    print("ARCHEOBRU_PHOTOGRAMMETRY_WITNESS_OK")
    quit(0)

func _render_asset(label: String, path: String) -> bool:
    var packed := load(path) as PackedScene
    if packed == null:
        _fail("could not load %s" % path)
        return false

    var stage := Node3D.new()
    stage.name = "PhotogrammetryStage_%s" % label
    root.add_child(stage)
    current_scene = stage

    var world_environment := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.16, 0.17, 0.18, 1.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.78, 0.81, 0.84, 1.0)
    environment.ambient_light_energy = 0.65
    environment.tonemap_mode = Environment.TONE_MAPPER_ACES
    world_environment.environment = environment
    stage.add_child(world_environment)

    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    key.light_energy = 1.35
    key.shadow_enabled = true
    stage.add_child(key)

    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-25.0, 145.0, 0.0)
    fill.light_energy = 0.38
    stage.add_child(fill)

    var wrapper := Node3D.new()
    wrapper.name = "AssetWrapper"
    stage.add_child(wrapper)
    var model := packed.instantiate() as Node3D
    if model == null:
        _fail("GLB root is not Node3D: %s" % path)
        stage.queue_free()
        return false
    wrapper.add_child(model)

    for _frame in range(4):
        await process_frame

    var bounds := _combined_world_bounds(model)
    if bounds.size.length() <= 0.0001:
        _fail("empty mesh bounds for %s" % label)
        stage.queue_free()
        return false

    var original_size := bounds.size
    var scale_factor := TARGET_HEIGHT_M / maxf(original_size.y, 0.001)
    wrapper.scale = Vector3.ONE * scale_factor
    for _frame in range(2):
        await process_frame
    bounds = _combined_world_bounds(model)

    # Normalize only inside the isolated witness. This is never a geographic
    # placement and must not be reused as production transform data.
    var center := bounds.position + bounds.size * 0.5
    wrapper.global_position += Vector3(-center.x, -bounds.position.y, -center.z)
    for _frame in range(2):
        await process_frame
    bounds = _combined_world_bounds(model)

    var camera := Camera3D.new()
    camera.fov = 52.0
    camera.near = 0.05
    camera.far = 500.0
    stage.add_child(camera)
    camera.current = true

    var normalized_center := bounds.position + bounds.size * 0.5
    var horizontal_extent := maxf(bounds.size.x, bounds.size.z)
    var distance := maxf(horizontal_extent * 1.8, bounds.size.y * 1.25)
    distance = maxf(distance, 10.0)

    for view_index in range(VIEW_ANGLES.size()):
        var yaw := float(VIEW_ANGLES[view_index])
        var direction := Vector3(sin(yaw), 0.10, cos(yaw)).normalized()
        camera.global_position = normalized_center + direction * distance
        camera.look_at(normalized_center + Vector3(0.0, bounds.size.y * 0.04, 0.0), Vector3.UP)
        await process_frame
        await RenderingServer.frame_post_draw
        var image := root.get_viewport().get_texture().get_image()
        if image == null or image.is_empty():
            _fail("empty witness image for %s view %d" % [label, view_index])
            stage.queue_free()
            return false
        var output := "%s/%s_view%d.png" % [OUTPUT_DIR, label, view_index]
        if image.save_png(output) != OK:
            _fail("could not save %s" % output)
            stage.queue_free()
            return false

    print("ARCHEOBRU_PHOTOGRAMMETRY_RENDER: label=%s source_size=%s normalized_size=%s" % [
        label, str(original_size), str(bounds.size)
    ])
    stage.queue_free()
    await process_frame
    return true

func _combined_world_bounds(root_node: Node3D) -> AABB:
    var has_bounds := false
    var minimum := Vector3.ZERO
    var maximum := Vector3.ZERO
    var candidates: Array[Node] = [root_node]
    candidates.append_array(root_node.find_children("*", "MeshInstance3D", true, false))
    for candidate: Node in candidates:
        if not candidate is MeshInstance3D:
            continue
        var mesh_instance := candidate as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        var aabb := mesh_instance.get_aabb()
        for corner_index in range(8):
            var corner := Vector3(
                aabb.position.x + (aabb.size.x if (corner_index & 1) != 0 else 0.0),
                aabb.position.y + (aabb.size.y if (corner_index & 2) != 0 else 0.0),
                aabb.position.z + (aabb.size.z if (corner_index & 4) != 0 else 0.0)
            )
            var world_corner := mesh_instance.global_transform * corner
            if not has_bounds:
                minimum = world_corner
                maximum = world_corner
                has_bounds = true
            else:
                minimum = minimum.min(world_corner)
                maximum = maximum.max(world_corner)
    if not has_bounds:
        return AABB()
    return AABB(minimum, maximum - minimum)

func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error("ARCHEOBRU_PHOTOGRAMMETRY_WITNESS_FAIL: " + message)
    print("ARCHEOBRU_PHOTOGRAMMETRY_WITNESS_FAIL: " + message)
    quit(1)
