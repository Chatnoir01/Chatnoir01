extends SceneTree

const SCENE_PATH := "res://game/zones/laeken_jette/laeken_playtest.tscn"
const VIEW_MANIFEST_PATH := "res://data/reference/laeken_jette/photo_match_views.json"
const OUTPUT_PATH := "res://laeken_playtest_current.png"


func _initialize() -> void:
    call_deferred("_run")


func _load_view() -> Dictionary:
    if not FileAccess.file_exists(VIEW_MANIFEST_PATH):
        push_error("PLAYTEST_CAPTURE_FAIL: photo-match manifest missing")
        return {}
    var file := FileAccess.open(VIEW_MANIFEST_PATH, FileAccess.READ)
    if file == null:
        push_error("PLAYTEST_CAPTURE_FAIL: photo-match manifest unreadable")
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if not (parsed is Dictionary):
        push_error("PLAYTEST_CAPTURE_FAIL: photo-match manifest invalid")
        return {}
    var views = parsed.get("views", [])
    if not (views is Array) or views.is_empty():
        push_error("PLAYTEST_CAPTURE_FAIL: photo-match manifest has no benchmark view")
        return {}

    var requested := OS.get_environment("PHOTO_MATCH_VIEW_ID").strip_edges()
    if requested.is_empty():
        if views[0] is Dictionary:
            return views[0] as Dictionary
        push_error("PLAYTEST_CAPTURE_FAIL: first benchmark view is invalid")
        return {}

    for item in views:
        if item is Dictionary and String(item.get("id", "")) == requested:
            return item as Dictionary
    push_error("PLAYTEST_CAPTURE_FAIL: requested benchmark view not found: %s" % requested)
    return {}


func _terrain_height(scene: Node, x: float, z: float) -> float:
    var terrain := scene.get_node_or_null("LaekenJetteZone/LaekenTerrain")
    if terrain != null and terrain.has_method("sample_height"):
        return float(terrain.call("sample_height", x, z))
    return 0.0


func _hide_benchmark_ui(node: Node, under_canvas_layer: bool = false) -> void:
    var in_ui := under_canvas_layer or node is CanvasLayer
    # The playtest scene currently owns root-level Labels/Controls rather than a
    # CanvasLayer. Photo-match evidence must contain world pixels only, so hide
    # all Control-derived UI plus any CanvasItems nested under a CanvasLayer.
    if node is Control:
        (node as Control).visible = false
    elif under_canvas_layer and node is CanvasItem:
        (node as CanvasItem).visible = false
    for child in node.get_children():
        _hide_benchmark_ui(child, in_ui)


func _apply_benchmark_camera(scene: Node, view: Dictionary) -> bool:
    var camera_xz = view.get("camera_game_xz", [])
    var target_xyz = view.get("target_game_xyz", [])
    if not (camera_xz is Array and camera_xz.size() >= 2 and target_xyz is Array and target_xyz.size() >= 3):
        push_error("PLAYTEST_CAPTURE_FAIL: benchmark camera coordinates invalid")
        return false

    var player_camera := scene.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera == null:
        push_error("PLAYTEST_CAPTURE_FAIL: player camera missing")
        return false
    player_camera.current = false

    var benchmark := Camera3D.new()
    benchmark.name = "PhotoMatchBenchmarkCamera"
    benchmark.fov = float(view.get("fov_degrees", 50.0))
    benchmark.near = 0.05
    benchmark.far = 15000.0
    scene.add_child(benchmark)

    var x := float(camera_xz[0])
    var z := float(camera_xz[1])
    var terrain_y := _terrain_height(scene, x, z)
    var eye_height := float(view.get("camera_height_above_terrain_m", 1.7))
    var y := terrain_y + eye_height

    if view.has("camera_game_y_from_atomium_baseline_m"):
        var pinned_y := float(view["camera_game_y_from_atomium_baseline_m"])
        if absf(y - pinned_y) > 0.35:
            push_error("PLAYTEST_CAPTURE_FAIL: runtime terrain disagrees with pinned DTM camera Y: runtime=%.3f pinned=%.3f" % [y, pinned_y])
            return false

    benchmark.global_position = Vector3(x, y, z)
    benchmark.look_at(Vector3(float(target_xyz[0]), float(target_xyz[1]), float(target_xyz[2])), Vector3.UP)
    benchmark.current = true
    print("PHOTO_MATCH_VIEW: %s camera=(%.3f,%.3f,%.3f) terrain=%.3f fov=%.1f" % [String(view.get("id", "unnamed")), x, y, z, terrain_y, benchmark.fov])
    return true


func _run() -> void:
    var view := _load_view()
    if view.is_empty():
        quit(1)
        return

    var resolution = view.get("resolution", [1280, 720])
    if not (resolution is Array and resolution.size() >= 2):
        push_error("PLAYTEST_CAPTURE_FAIL: benchmark resolution invalid")
        quit(1)
        return
    root.size = Vector2i(int(resolution[0]), int(resolution[1]))

    var packed: PackedScene = load(SCENE_PATH)
    if packed == null:
        push_error("PLAYTEST_CAPTURE_FAIL: scene did not load")
        quit(1)
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)
    _hide_benchmark_ui(scene)

    # Allow DTM, UrbIS drape, height/material passes and corridor geometry to settle.
    for _i in range(60):
        await process_frame

    if not _apply_benchmark_camera(scene, view):
        scene.queue_free()
        await process_frame
        quit(1)
        return

    for _i in range(8):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    await process_frame

    var image: Image = root.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("PLAYTEST_CAPTURE_FAIL: viewport image empty")
        quit(1)
        return

    var error := image.save_png(OUTPUT_PATH)
    if error != OK:
        push_error("PLAYTEST_CAPTURE_FAIL: save_png error %s" % error)
        quit(1)
        return

    print("PLAYTEST_CAPTURE_OK: %s %dx%d view=%s" % [OUTPUT_PATH, image.get_width(), image.get_height(), String(view.get("id", "unnamed"))])
    scene.queue_free()
    await process_frame
    quit(0)
