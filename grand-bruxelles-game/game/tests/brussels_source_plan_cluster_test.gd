extends SceneTree

const PLAYABILITY_RUNTIME_SCRIPT := preload("res://game/scripts/mobile_playability_collision_runtime.gd")
const EAST_CELL_ID := "bxl-e149500-n169000-s500"
const EXPECTED_SOURCE_BUILDINGS := 919
const EXPECTED_VISUAL_BUILDINGS := 584
const EXPECTED_BLOCKED_BUILDINGS := EXPECTED_SOURCE_BUILDINGS - EXPECTED_VISUAL_BUILDINGS
const CAPTURE_OUTPUT := "res://artifacts/ixelles/ixelles_source_plan_east_1280x720.png"
const CAPTURE_BEFORE_OUTPUT := "res://artifacts/ixelles/ixelles_source_plan_east_massing_flat_before_1280x720.png"
const CAPTURE_WIDTH := 1280
const CAPTURE_HEIGHT := 720
const MIN_GT3_FRACTION := 0.020
const MIN_GT8_FRACTION := 0.0075
const LEGACY_FLAT_MASSING_COLOR := Color(0.60, 0.53, 0.45, 1.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_SOURCE_PLAN_CLUSTER_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _contains_static_body(node: Node) -> bool:
    if node is StaticBody3D:
        return true
    for child: Node in node.get_children():
        if _contains_static_body(child):
            return true
    return false

func _capture_requested() -> bool:
    for arg: String in OS.get_cmdline_user_args():
        if arg.strip_edges().to_lower() == "capture=1":
            return true
    return false

func _render_image() -> Image:
    for _frame: int in range(4):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    return root.get_texture().get_image()

func _save_image(image: Image, output: String) -> bool:
    if image == null or image.is_empty() or image.get_width() != CAPTURE_WIDTH or image.get_height() != CAPTURE_HEIGHT:
        _fail("east visual capture invalid: %dx%d" % [image.get_width() if image != null else 0, image.get_height() if image != null else 0])
        return false
    var absolute_output := ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("east visual capture save failed: %s" % output)
        return false
    return true

func _compare_images(before: Image, after: Image) -> Dictionary:
    var gt3 := 0
    var gt8 := 0
    var total := CAPTURE_WIDTH * CAPTURE_HEIGHT
    for y: int in range(CAPTURE_HEIGHT):
        for x: int in range(CAPTURE_WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                gt3 += 1
            if delta > 8.0:
                gt8 += 1
    return {
        "gt3": gt3,
        "gt8": gt8,
        "gt3_fraction": float(gt3) / float(total),
        "gt8_fraction": float(gt8) / float(total),
    }

func _capture_east_visual(world: Node3D, center: Vector3, source_cell: Node) -> bool:
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.66, 0.73, 0.82, 1.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.76, 0.78, 0.82, 1.0)
    environment.ambient_light_energy = 0.85
    var world_environment := WorldEnvironment.new()
    world_environment.environment = environment
    world.add_child(world_environment)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
    light.light_energy = 1.35
    light.shadow_enabled = true
    world.add_child(light)

    var camera := Camera3D.new()
    camera.fov = 56.0
    camera.near = 0.5
    camera.far = 2500.0
    camera.position = center + Vector3(330.0, 185.0, 330.0)
    world.add_child(camera)
    camera.look_at(center + Vector3(0.0, 12.0, 0.0), Vector3.UP)
    camera.current = true

    var massing := source_cell.find_child("VisualCandidateBuildingMassing", true, false) as MeshInstance3D
    if not _expect(massing != null and massing.mesh != null and massing.mesh.get_surface_count() == 1, "massing A/B target missing"):
        return false
    var material := massing.mesh.surface_get_material(0) as StandardMaterial3D
    if not _expect(material != null and material.vertex_color_use_as_albedo, "production massing material is not vertex-color driven"):
        return false

    material.vertex_color_use_as_albedo = false
    material.albedo_color = LEGACY_FLAT_MASSING_COLOR
    var before := await _render_image()
    if not _save_image(before, CAPTURE_BEFORE_OUTPUT):
        return false

    material.albedo_color = Color.WHITE
    material.vertex_color_use_as_albedo = true
    var after := await _render_image()
    if not _save_image(after, CAPTURE_OUTPUT):
        return false

    var metrics := _compare_images(before, after)
    if not _expect(float(metrics["gt3_fraction"]) >= MIN_GT3_FRACTION, "massing tone A/B gt3 impact below %.4f: %.6f" % [MIN_GT3_FRACTION, float(metrics["gt3_fraction"])]):
        return false
    if not _expect(float(metrics["gt8_fraction"]) >= MIN_GT8_FRACTION, "massing tone A/B gt8 impact below %.4f: %.6f" % [MIN_GT8_FRACTION, float(metrics["gt8_fraction"])]):
        return false
    print("BRUSSELS_SOURCE_PLAN_MASSING_AB_OK: gt3=%d fraction=%.6f gt8=%d fraction=%.6f thresholds=%.4f/%.4f" % [int(metrics["gt3"]), float(metrics["gt3_fraction"]), int(metrics["gt8"]), float(metrics["gt8_fraction"]), MIN_GT3_FRACTION, MIN_GT8_FRACTION])
    print("BRUSSELS_SOURCE_PLAN_CAPTURE_OK: before=%s after=%s size=%dx%d" % [CAPTURE_BEFORE_OUTPUT, CAPTURE_OUTPUT, CAPTURE_WIDTH, CAPTURE_HEIGHT])
    return true

func _run() -> void:
    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)

    var player := CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(-652.0, 1.05, 621.0)
    world.add_child(player)

    var playability := PLAYABILITY_RUNTIME_SCRIPT.new()
    playability.name = "MobilePlayabilityCollisionRuntime"
    world.add_child(playability)

    var runtime: BrusselsWorldStreamingRuntime = null
    for _frame: int in range(16):
        await process_frame
        runtime = world.get_node_or_null("WorldStreamingRuntime") as BrusselsWorldStreamingRuntime
        if runtime != null and runtime.runtime_ready:
            break
    if not _expect(runtime != null and runtime.runtime_ready, "production runtime did not become ready"):
        return

    var scheduler_metrics: Dictionary = runtime.manager.get_metrics()
    if not _expect(int(scheduler_metrics.get("registered_cells", 0)) == 4, "four-cell cluster was not registered"):
        return

    var descriptor := runtime.manager.get_cell_descriptor(EAST_CELL_ID)
    var center: Vector3 = descriptor.get("world_center", Vector3.ZERO)
    if not _expect(center != Vector3.ZERO, "east source cell has no world center"):
        return

    player.global_position = center + Vector3(600.0, 1.05, 0.0)
    player.velocity = Vector3(-100.0, 0.0, 0.0)
    var source_cell: Node = null
    for _frame: int in range(140):
        await physics_frame
        await process_frame
        if runtime.backend.has_active_instance(EAST_CELL_ID):
            source_cell = runtime.backend.get_instance(EAST_CELL_ID)
            if is_instance_valid(source_cell) and bool(source_cell.get("runtime_loaded")):
                break

    if not _expect(is_instance_valid(source_cell) and bool(source_cell.get("runtime_loaded")), "east source-plan cell did not stream in"):
        return
    if not _expect(int(source_cell.get("street_surface_count")) == 252, "east source-plan street surface count drifted"):
        return
    if not _expect(int(source_cell.get("source_building_count")) == EXPECTED_SOURCE_BUILDINGS, "east source building count drifted"):
        return
    if not _expect(bool(source_cell.get("strong_height_contract_loaded")), "east strong-height visual contract was not consumed"):
        return
    if not _expect(int(source_cell.get("rendered_building_count")) == EXPECTED_VISUAL_BUILDINGS, "eligible visual building massing count drifted"):
        return
    if not _expect(int(source_cell.get("massing_tone_profile_count")) >= 4, "visual massing lacks deterministic shared tone variation"):
        return
    if not _expect(int(source_cell.get("blocked_unapproved_building_count")) == EXPECTED_BLOCKED_BUILDINGS, "non-eligible building heights were not fail-closed"):
        return
    if not _expect(source_cell.find_child("VisualCandidateBuildingMassing", true, false) != null, "combined visual building massing mesh is missing"):
        return
    if not _expect(source_cell.find_child("OfficialBrusselsStreetSurfaces", true, false) != null, "source-backed street surface mesh is missing"):
        return
    if not _expect(int(source_cell.get("street_surface_chunks")) > 1, "source-plan surfaces were not chunked across frames"):
        return
    if not _expect(int(source_cell.get("building_massing_chunks")) > 1, "visual building massing was not chunked across frames"):
        return
    if not _expect(int(source_cell.call("get_max_stream_phase_ms")) <= 50, "source-plan build exceeded 50 ms phase guard"):
        return

    if _capture_requested():
        if not await _capture_east_visual(world, center, source_cell):
            return

    player.global_position = center + Vector3(40.0, 1.05, 0.0)
    player.velocity = Vector3.ZERO
    for _frame: int in range(5):
        await physics_frame
        await process_frame
    if not _expect(runtime.manager.is_collision_active(EAST_CELL_ID), "scheduler did not enter near-player tier for east cell"):
        return
    if not _expect(not _contains_static_body(source_cell), "visual candidate massing invented gameplay collision"):
        return

    player.global_position = center + Vector3(900.0, 1.05, 0.0)
    for _frame: int in range(10):
        await physics_frame
        await process_frame
    if not _expect(not runtime.backend.has_active_instance(EAST_CELL_ID), "east source-plan cell did not unload outside hysteresis radius"):
        return

    print("BRUSSELS_SOURCE_PLAN_CLUSTER_OK: east cell streamed 252 official street surfaces, rendered 584 cross-source visual building candidates in a combined mesh with %d non-classifying tone profiles, kept 335 buildings fail-closed, created no fake collision, and unloaded cleanly" % int(source_cell.get("massing_tone_profile_count")))
    world.queue_free()
    quit(0)