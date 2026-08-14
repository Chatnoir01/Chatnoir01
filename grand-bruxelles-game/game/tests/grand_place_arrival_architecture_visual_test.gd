extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/arrival-architecture"
const WIDTH := 1280
const HEIGHT := 720
const GRAND_PLACE_ANCHOR := Vector2(319.01, -535.2)
# Presentation witness only. This point is deliberately inside the official Grand-Place
# surface and aims across the plaza at existing production architecture. It is not a
# surveyed camera pose and does not establish landmark dimensions.
const CAMERA_POSITION := Vector3(289.0, 1.72, -563.0)
const CAMERA_TARGET := Vector3(350.0, 13.0, -505.0)
const CAMERA_FOV := 62.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_ARRIVAL_ARCH_FAIL: %s" % message)
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
    for _frame: int in range(4):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _nearby_architecture(main: Node) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var buildings_root := main.get_node_or_null("BrusselsOSM/GeneratedBuildings")
    if buildings_root == null:
        return result
    for child: Node in buildings_root.get_children():
        if not child is Node3D or not child.name.begins_with("Building_"):
            continue
        var node := child as Node3D
        var xz := Vector2(node.global_position.x, node.global_position.z)
        var distance := xz.distance_to(GRAND_PLACE_ANCHOR)
        if distance > 150.0:
            continue
        result.append({
            "name": child.name,
            "position": node.global_position,
            "distance": distance,
        })
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
    return result

func _visible_architecture_count(nearby: Array[Dictionary], camera: Camera3D) -> int:
    var count := 0
    for entry: Dictionary in nearby:
        var position: Vector3 = entry["position"]
        if camera.is_position_in_frustum(position):
            count += 1
    return count

func _run() -> void:
    var surface := root.get_node_or_null("GrandPlaceOfficialSurface")
    if surface == null:
        _fail("autoloaded official Grand-Place surface missing")
        return
    for _frame: int in range(4):
        await process_frame
    if not bool(surface.get("surface_loaded")):
        _fail("official Grand-Place surface did not load")
        return
    if int(surface.get("official_area_m2")) != 5337 or int(surface.get("open_vertex_count")) != 99:
        _fail("official surface source contract drifted")
        return
    if bool(surface.get_meta("runtime_approved", true)) or bool(surface.get_meta("realism_complete", true)):
        _fail("provisional realism gates were lost")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(12):
        await process_frame
    _hide_noise(main)

    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlaceArrivalArchitectureWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(2):
        await process_frame

    var nearby := _nearby_architecture(main)
    var diagnostic: Array[String] = []
    for index: int in range(mini(nearby.size(), 20)):
        var entry: Dictionary = nearby[index]
        var p: Vector3 = entry["position"]
        diagnostic.append("%s@(%.1f,%.1f,%.1f):%.1fm" % [str(entry["name"]), p.x, p.y, p.z, float(entry["distance"])])
    print("GRAND_PLACE_NEARBY_ARCH: count=%d nearest=%s" % [nearby.size(), "; ".join(diagnostic)])

    # Always capture the calibrated baseline before enforcing the architecture gate so a
    # failing witness remains visually diagnosable instead of producing a log-only artifact.
    surface.call("set_surface_visible", false)
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    var visible_architecture := _visible_architecture_count(nearby, camera)
    if visible_architecture < 3:
        _fail("witness does not carry enough production architecture: %d visible of %d nearby building masses" % [visible_architecture, nearby.size()])
        return

    surface.call("set_surface_visible", true)
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("GRAND_PLACE_ARRIVAL_ARCH_OK: area=%d vertices=%d triangles=%d visible_architecture=%d nearby=%d camera=(%.1f,%.2f,%.1f) target=(%.1f,%.1f,%.1f) fov=%.1f before=%s after=%s" % [
        int(surface.get("official_area_m2")), int(surface.get("open_vertex_count")), int(surface.get("triangle_count")), visible_architecture, nearby.size(),
        CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        CAMERA_TARGET.x, CAMERA_TARGET.y, CAMERA_TARGET.z,
        CAMERA_FOV, OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
