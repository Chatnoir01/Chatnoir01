extends SceneTree

const SCENE_PATH := "res://game/zones/laeken_jette/laeken_playtest.tscn"
const CANDIDATE_PATH := "res://data/reference/laeken_jette/heysel_stadium_camera_candidates.json"
const OUTPUT_92M := "res://heysel_from_atomium_92m_v2.png"
const OUTPUT_36M := "res://heysel_from_atomium_36m_v2.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("HEYSEL_CAMERA_CAPTURE_FAIL: %s" % message)
    quit(1)

func _load_candidates() -> Dictionary:
    if not FileAccess.file_exists(CANDIDATE_PATH):
        return {}
    var file := FileAccess.open(CANDIDATE_PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _hide_ui(node: Node, under_canvas_layer: bool = false) -> void:
    var in_ui := under_canvas_layer or node is CanvasLayer
    if node is Control:
        (node as Control).visible = false
    elif under_canvas_layer and node is CanvasItem:
        (node as CanvasItem).visible = false
    for child in node.get_children():
        _hide_ui(child, in_ui)

func _capture_candidate(scene: Node, candidate: Dictionary, output_path: String) -> bool:
    var camera_xyz = candidate.get("camera_game_xyz", [])
    var target_xyz = candidate.get("target_game_xyz", [])
    var resolution = candidate.get("resolution", [1280, 720])
    if not (camera_xyz is Array and camera_xyz.size() >= 3 and target_xyz is Array and target_xyz.size() >= 3):
        push_error("HEYSEL_CAMERA_CAPTURE_FAIL: invalid camera/target coordinates")
        return false
    if not (resolution is Array and resolution.size() >= 2):
        push_error("HEYSEL_CAMERA_CAPTURE_FAIL: invalid resolution")
        return false

    root.size = Vector2i(int(resolution[0]), int(resolution[1]))
    var old := scene.get_node_or_null("HeyselBenchmarkCamera")
    if old != null:
        old.queue_free()
        await process_frame

    var camera := Camera3D.new()
    camera.name = "HeyselBenchmarkCamera"
    camera.fov = float(candidate.get("fov_degrees", 50.0))
    camera.near = 0.05
    camera.far = 15000.0
    scene.add_child(camera)
    camera.global_position = Vector3(float(camera_xyz[0]), float(camera_xyz[1]), float(camera_xyz[2]))
    camera.look_at(Vector3(float(target_xyz[0]), float(target_xyz[1]), float(target_xyz[2])), Vector3.UP)
    camera.current = true

    for _i in range(10):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    await process_frame

    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("HEYSEL_CAMERA_CAPTURE_FAIL: empty viewport image")
        return false
    var err := image.save_png(output_path)
    if err != OK:
        push_error("HEYSEL_CAMERA_CAPTURE_FAIL: save_png failed: %s" % err)
        return false
    print("HEYSEL_CAMERA_CAPTURE: %s camera=%s target=%s fov=%.1f" % [String(candidate.get("id", "unknown")), camera.global_position, Vector3(float(target_xyz[0]), float(target_xyz[1]), float(target_xyz[2])), camera.fov])
    return true

func _run() -> void:
    var data := _load_candidates()
    if data.is_empty():
        _fail("candidate registry missing or invalid")
        return
    var candidates = data.get("candidates", [])
    if not (candidates is Array and candidates.size() == 2):
        _fail("expected exactly two provisional Atomium observation candidates")
        return

    var packed: PackedScene = load(SCENE_PATH)
    if packed == null:
        _fail("playtest scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    _hide_ui(scene)
    for _i in range(60):
        await process_frame

    if not await _capture_candidate(scene, candidates[0] as Dictionary, OUTPUT_92M):
        quit(1)
        return
    if not await _capture_candidate(scene, candidates[1] as Dictionary, OUTPUT_36M):
        quit(1)
        return

    print("HEYSEL_CAMERA_CAPTURE_OK: rendered v2 92m and 36m provisional comparison views")
    scene.queue_free()
    await process_frame
    quit(0)
