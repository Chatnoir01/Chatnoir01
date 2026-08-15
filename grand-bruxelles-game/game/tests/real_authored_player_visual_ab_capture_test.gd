extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const OUTPUT_DIR := "res://artifacts/qa/real_authored_player_visual_ab"
const BEFORE_PATH := OUTPUT_DIR + "/before.png"
const AFTER_PATH := OUTPUT_DIR + "/after.png"
const HUMANOID_VISUAL := preload("res://game/scripts/humanoid_visual.gd")
const REAL_ASSET := "res://assets/characters/player/kaykit_rogue/Rogue.glb"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("REAL_AUTHORED_PLAYER_VISUAL_AB_FAIL: %s" % message)
    quit(1)

func _capture(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return null
    return image

func _metrics(before: Image, after: Image) -> Dictionary:
    if before == null or after == null or before.get_size() != after.get_size():
        return {}
    var changed_4 := 0
    var changed_12 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var t4 := 4.0 / 255.0
    var t12 := 12.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if d > t4:
                changed_4 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if d > t12:
                changed_12 += 1
    var total := float(WIDTH * HEIGHT)
    return {
        "changed_4_fraction": float(changed_4) / total,
        "changed_12_fraction": float(changed_12) / total,
        "bbox_width": 0 if max_x < min_x else max_x - min_x + 1,
        "bbox_height": 0 if max_y < min_y else max_y - min_y + 1,
    }

func _make_world(viewport: SubViewport) -> Node3D:
    var world := Node3D.new()
    viewport.add_child(world)

    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.12, 0.13, 0.15, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.82, 0.84, 0.88, 1.0)
    env.ambient_light_energy = 0.72
    environment.environment = env
    world.add_child(environment)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    light.light_energy = 1.45
    light.shadow_enabled = true
    world.add_child(light)

    var camera := Camera3D.new()
    camera.position = Vector3(0.0, 1.15, 4.2)
    camera.fov = 46.0
    world.add_child(camera)
    camera.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)
    camera.current = true

    var floor_mesh := PlaneMesh.new()
    floor_mesh.size = Vector2(8.0, 8.0)
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color(0.24, 0.25, 0.27, 1.0)
    floor_material.roughness = 0.95
    floor_mesh.material = floor_material
    var floor_instance := MeshInstance3D.new()
    floor_instance.mesh = floor_mesh
    floor_instance.position.y = -0.90
    world.add_child(floor_instance)
    return world

func _make_player(world: Node3D, authored: bool) -> CharacterBody3D:
    var actor := CharacterBody3D.new()
    actor.name = "Player"
    world.add_child(actor)
    var visual := HUMANOID_VISUAL.new()
    visual.name = "VisualUpgrade"
    if authored:
        visual.authored_scene_path = REAL_ASSET
        visual.allow_authored_fallback_paths = false
    else:
        visual.authored_scene_path = ""
        visual.allow_authored_fallback_paths = false
    actor.add_child(visual)
    return actor

func _run() -> void:
    if not ResourceLoader.exists(REAL_ASSET):
        _fail("real authored GLB missing")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var world := _make_world(viewport)

    var before_actor := _make_player(world, false)
    for _frame: int in range(12):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)
    if before == null:
        _fail("could not capture procedural BEFORE")
        return
    before_actor.queue_free()
    await process_frame

    var after_actor := _make_player(world, true)
    for _frame: int in range(12):
        await process_frame
    var visual := after_actor.get_node_or_null("VisualUpgrade")
    if visual == null or not visual.call("is_using_authored_character"):
        _fail("AFTER did not select authored player")
        return
    if String(visual.call("resolved_authored_scene_path")) != REAL_ASSET:
        _fail("AFTER resolved unexpected authored asset")
        return
    var after := await _capture(viewport, AFTER_PATH)
    if after == null:
        _fail("could not capture authored AFTER")
        return

    var metrics := _metrics(before, after)
    if metrics.is_empty():
        _fail("could not compare A/B")
        return
    var changed_4 := float(metrics["changed_4_fraction"])
    var changed_12 := float(metrics["changed_12_fraction"])
    var bbox_width := int(metrics["bbox_width"])
    var bbox_height := int(metrics["bbox_height"])
    print("REAL_AUTHORED_PLAYER_VISUAL_AB_METRICS: gt4=%.4f%% gt12=%.4f%% bbox=%dx%d asset=%s" % [changed_4 * 100.0, changed_12 * 100.0, bbox_width, bbox_height, REAL_ASSET])
    if changed_4 < 0.015:
        _fail("authored player visual change too small: %.4f%%" % (changed_4 * 100.0))
        return
    if changed_12 < 0.008:
        _fail("strong authored player visual change too small: %.4f%%" % (changed_12 * 100.0))
        return
    if bbox_width < 180 or bbox_height < 260:
        _fail("authored player too small/localized in witness: bbox=%dx%d" % [bbox_width, bbox_height])
        return
    print("REAL_AUTHORED_PLAYER_VISUAL_AB_OK: %s %s" % [BEFORE_PATH, AFTER_PATH])
    viewport.queue_free()
    quit(0)
