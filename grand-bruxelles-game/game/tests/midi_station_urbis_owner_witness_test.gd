extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/midi_m3_station_before.png"
const AFTER_PATH := "res://artifacts/visual/midi_m3_station_after.png"
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)
const MIN_CHANGED_3 := 0.08
const MIN_CHANGED_8 := 0.05
const MIN_BBOX_WIDTH := 700
const MIN_BBOX_HEIGHT := 250

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_M3_URBIS_OWNER_VISUAL_FAIL: %s" % message)
    quit(1)

func _hide_canvas(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child in node.get_children():
        _hide_canvas(child)

func _freeze(scene: Node3D) -> void:
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D: (traffic as Node3D).visible = false
    for path in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var n := scene.get_node_or_null(path) as Node3D
        if n != null: n.visible = false
    var player := scene.get_node_or_null("Player") as Node3D
    if player != null: player.visible = false
    _hide_canvas(scene)

func _capture(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != Vector2i(WIDTH, HEIGHT):
        return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return null
    return image

func _stats(before: Image, after: Image, threshold: int) -> Dictionary:
    var changed := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var limit := float(threshold) / 255.0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if d > limit:
                changed += 1
                min_x = mini(min_x, x); min_y = mini(min_y, y)
                max_x = maxi(max_x, x); max_y = maxi(max_y, y)
    var bbox := Rect2i()
    if changed > 0:
        bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    return {"fraction": float(changed) / float(WIDTH * HEIGHT), "bbox": bbox}

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main missing"); return
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var scene := packed.instantiate() as Node3D
    viewport.add_child(scene)
    for _i in range(90): await process_frame
    _freeze(scene)

    var hero := scene.get_node_or_null("MidiHeroZone") as Node3D
    var urbis := scene.get_node_or_null("UrbISMidiExact") as Node3D
    if hero == null or urbis == null:
        _fail("Midi production owners missing"); return
    if hero.get_node_or_null("BruxellesMidiStation") != null:
        _fail("production AFTER still builds hand-authored station complex"); return
    for required in ["MidiMainEntranceFonsny", "FonsnyForecourt"]:
        if hero.get_node_or_null(required) == null:
            _fail("required street-level detail missing: %s" % required); return

    var camera := Camera3D.new()
    camera.fov = 69.0
    scene.add_child(camera)
    camera.look_at_from_position(ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 1.65, 0.0), ENTRANCE + Vector3(0.0, 3.2, 0.0), Vector3.UP)
    camera.current = true

    # Recreate the legacy hand-built station mass only for the deterministic BEFORE.
    hero.call("_build_station_complex")
    for _i in range(3): await process_frame
    var legacy := hero.get_node_or_null("BruxellesMidiStation") as Node3D
    if legacy == null:
        _fail("could not reconstruct legacy BEFORE mass"); return
    var before := await _capture(viewport, BEFORE_PATH)
    if before == null:
        _fail("BEFORE capture missing"); return

    legacy.queue_free()
    for _i in range(4): await process_frame
    if hero.get_node_or_null("BruxellesMidiStation") != null:
        _fail("legacy station mass survived AFTER"); return
    var after := await _capture(viewport, AFTER_PATH)
    if after == null:
        _fail("AFTER capture missing"); return

    var s3 := _stats(before, after, 3)
    var s8 := _stats(before, after, 8)
    var f3 := float(s3["fraction"])
    var f8 := float(s8["fraction"])
    var bbox := s3["bbox"] as Rect2i
    print("MIDI_M3_URBIS_OWNER_METRICS: gt3=%.4f%% gt8=%.4f%% bbox=%dx%d" % [f3 * 100.0, f8 * 100.0, bbox.size.x, bbox.size.y])
    if f3 < MIN_CHANGED_3 or f8 < MIN_CHANGED_8:
        _fail("station-mass correction below predeclared full-frame impact gate"); return
    if bbox.size.x < MIN_BBOX_WIDTH or bbox.size.y < MIN_BBOX_HEIGHT:
        _fail("station-mass correction bbox too small"); return
    if hero.get_node_or_null("MidiMainEntranceFonsny") == null or scene.get_node_or_null("UrbISMidiExact") == null:
        _fail("source-backed/street-level owner lost after A/B"); return
    print("MIDI_M3_URBIS_OWNER_VISUAL_OK before=%s after=%s" % [BEFORE_PATH, AFTER_PATH])
    quit(0)
