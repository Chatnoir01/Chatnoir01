extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 100

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_PROCEDURAL_FALLBACK_CAPTURE_FAIL: %s" % message)
    quit(1)

func _hide_qa_noise(scene: Node) -> void:
    for node_path: String in ["PrototypeLabel", "ABLabel"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false

func _material_color(material: Material) -> String:
    if material is StandardMaterial3D:
        return str((material as StandardMaterial3D).albedo_color)
    return "none"

func _hide_visual_metrics(before: Image, after: Image) -> String:
    var changed := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var threshold := 4.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta > threshold:
                changed += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var fraction := float(changed) / float(WIDTH * HEIGHT)
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    return "changed=%.4f%% bbox=%dx%d" % [fraction * 100.0, bbox_width, bbox_height]

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        _fail("expected exactly one output PNG path")
        return
    var output_path := args[0]
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    _hide_qa_noise(scene)
    viewport.add_child(scene)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_qa_noise(scene)

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    var visual := scene.get_node_or_null("Player/VisualUpgrade") as Node3D
    if player == null or visual == null:
        _fail("production player visual path missing")
        return
    if visual.call("is_using_authored_character"):
        _fail("capture requires current procedural player fallback")
        return
    var camera := viewport.get_camera_3d()
    if camera == null:
        _fail("normal gameplay camera missing")
        return

    var torso := visual.get_node_or_null("Torso") as MeshInstance3D
    var torso_surface_color := Color(0, 0, 0, 0)
    var active_material: Material = null
    if torso != null and torso.mesh is ArrayMesh and (torso.mesh as ArrayMesh).get_surface_count() > 0:
        var torso_material := (torso.mesh as ArrayMesh).surface_get_material(0) as StandardMaterial3D
        if torso_material != null:
            torso_surface_color = torso_material.albedo_color
        active_material = torso.get_active_material(0)
    print("PLAYER_PROCEDURAL_FALLBACK_CAPTURE_RENDERER: signature=%s torso_mesh=%s surface_color=%s active_color=%s override_color=%s overlay_color=%s legacy_visible=%s" % [str(visual.call("visual_signature")), torso.mesh.get_class() if torso != null and torso.mesh != null else "missing", str(torso_surface_color), _material_color(active_material), _material_color(torso.material_override if torso != null else null), _material_color(torso.material_overlay if torso != null else null), str((scene.get_node_or_null("Player/MeshInstance3D") as MeshInstance3D).visible if scene.get_node_or_null("Player/MeshInstance3D") is MeshInstance3D else false)])

    scene.process_mode = Node.PROCESS_MODE_DISABLED
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("capture image is empty")
        return
    var absolute := output_path if output_path.begins_with("/") else ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        _fail("could not save PNG")
        return

    visual.visible = false
    RenderingServer.force_draw()
    await process_frame
    var hidden_image := viewport.get_texture().get_image()
    if hidden_image == null or hidden_image.is_empty():
        _fail("hidden-player diagnostic image is empty")
        return
    var torso_screen := camera.unproject_position(torso.global_position) if torso != null else Vector2(-1, -1)
    var sample_x := clampi(int(round(torso_screen.x)), 0, WIDTH - 1)
    var sample_y := clampi(int(round(torso_screen.y)), 0, HEIGHT - 1)
    print("PLAYER_PROCEDURAL_FALLBACK_HIDE_VISUAL_METRICS: %s torso_screen=%s normal_pixel=%s hidden_pixel=%s" % [_hide_visual_metrics(image, hidden_image), str(torso_screen), str(image.get_pixel(sample_x, sample_y)), str(hidden_image.get_pixel(sample_x, sample_y))])
    visual.visible = true

    print("PLAYER_PROCEDURAL_FALLBACK_CAPTURE_OK: %s player=%s camera=%s" % [absolute, str(player.global_position), str(camera.global_position)])
    viewport.queue_free()
    quit(0)
