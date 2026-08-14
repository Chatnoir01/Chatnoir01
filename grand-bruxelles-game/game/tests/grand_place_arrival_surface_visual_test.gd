extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/arrival-surface"
const WIDTH := 1280
const HEIGHT := 720
# Presentation witness only: source-bounded Grand-Place arrival viewpoint inside the
# official surface envelope. It is not a surveyed camera pose.
const CAMERA_POSITION := Vector3(305.0, 1.72, -572.0)
const CAMERA_TARGET := Vector3(333.0, 0.85, -521.0)
const CAMERA_FOV := 58.0


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("GRAND_PLACE_ARRIVAL_SURFACE_FAIL: %s" % message)
    quit(1)


func _hide_noise(main: Node) -> void:
    for name_value: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls", "PrototypeLabel"]:
        var node := main.get_node_or_null(name_value)
        if node is CanvasItem:
            (node as CanvasItem).visible = false
    for path: String in ["Player", "PrototypeCar", "TrafficManager", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node is Node3D:
            (node as Node3D).visible = false


func _capture(path: String) -> bool:
    for _frame: int in range(3):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK


func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(12):
        await process_frame

    var surface := main.get_node_or_null("GrandPlaceOfficialSurface")
    if surface == null or not bool(surface.get("surface_loaded")):
        _fail("production Grand-Place official surface did not load")
        return
    if int(surface.get("official_area_m2")) != 5337:
        _fail("official area drifted")
        return
    if int(surface.get("open_vertex_count")) != 99:
        _fail("official open vertex count drifted")
        return
    if int(surface.get("triangle_count")) <= 80:
        _fail("official surface triangulation unexpectedly sparse")
        return
    if str(surface.get_meta("official_inspire_id", "")) != "https://databrussels.be/id/streetsurface/42405":
        _fail("official source identity drifted")
        return
    if bool(surface.get_meta("runtime_approved", true)) or bool(surface.get_meta("realism_complete", true)):
        _fail("provisional realism gates were lost")
        return

    _hide_noise(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlaceArrivalWitnessCamera"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true

    # Pixel-stable A/B: only surface visibility changes. The target stays near eye/ground
    # level so the official 5,337 m2 plaza occupies meaningful foreground screen area.
    surface.call("set_surface_visible", false)
    if bool(surface.call("surface_is_visible")):
        _fail("official surface refused baseline hide")
        return
    if not await _capture(OUTPUT_DIR + "/baseline.png"):
        _fail("baseline capture failed")
        return

    surface.call("set_surface_visible", true)
    if not bool(surface.call("surface_is_visible")):
        _fail("official surface refused visible witness state")
        return
    if not await _capture(OUTPUT_DIR + "/official_surface.png"):
        _fail("official-surface capture failed")
        return

    print("GRAND_PLACE_ARRIVAL_SURFACE_OK: area=%d vertices=%d triangles=%d camera=(%.2f, %.2f, %.2f) target=(%.2f, %.2f, %.2f) fov=%.1f baseline=%s official=%s" % [
        int(surface.get("official_area_m2")), int(surface.get("open_vertex_count")), int(surface.get("triangle_count")),
        CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        CAMERA_TARGET.x, CAMERA_TARGET.y, CAMERA_TARGET.z,
        CAMERA_FOV, OUTPUT_DIR + "/baseline.png", OUTPUT_DIR + "/official_surface.png"
    ])
    quit(0)
