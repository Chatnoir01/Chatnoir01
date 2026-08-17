extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_official_paved_forecourt_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_official_paved_forecourt_after.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.030
const MIN_CHANGED_OVER_8 := 0.015
const MIN_BBOX_WIDTH := 700
const MIN_BBOX_HEIGHT := 160

# Reuse the exact frozen production-player witness already accepted for the
# shipped Midi station-envelope A/B. Do not move the camera to rescue this lot.
const MIDI := Vector3(-668.5, 0.0, 627.84)
const STATION_SIDE := Vector3(-0.779, 0.0, -0.627)
const CAMERA_POSITION := Vector3(-652.0, 1.72, 621.0)
const TARGET := MIDI + STATION_SIDE * 12.0 + Vector3(0.0, 5.5, 0.0)
const CAMERA_FOV := 69.0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var world := packed.instantiate()
    var traffic_manager := world.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    get_root().add_child(world)
    current_scene = world
    for _frame: int in range(70):
        await process_frame
    _freeze_and_mask_dynamics(world)

    var runtime := get_root().get_node_or_null("MidiOfficialPavedForecourtRuntime")
    if runtime == null:
        _fail("paved forecourt autoload missing")
        return
    for _frame: int in range(40):
        if bool(runtime.get("applied")):
            break
        await process_frame
    if not bool(runtime.get("applied")):
        _fail("paved forecourt runtime did not apply")
        return
    if int(runtime.get("paved_feature_count")) <= 0:
        _fail("no official paved UrbIS features reached runtime")
        return
    var enhanced := runtime.call("enhanced_material") as ShaderMaterial
    if enhanced == null:
        _fail("enhanced paved material missing")
        return
    if bool(enhanced.get_meta("geometry_changed", true)):
        _fail("A/B candidate must remain material-only")
        return

    var gameplay_camera := get_root().get_viewport().get_camera_3d()
    if gameplay_camera != null:
        gameplay_camera.current = false
    var camera := Camera3D.new()
    camera.name = "MidiOfficialPavedForecourtFrozenPlayerWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    world.add_child(camera)
    camera.look_at(TARGET, Vector3.UP)
    camera.current = true
    _freeze_and_mask_dynamics(world)
    world.process_mode = Node.PROCESS_MODE_DISABLED

    runtime.call("set_enhanced_material_enabled", false)
    var before := await _capture(BEFORE_PATH)
    runtime.call("set_enhanced_material_enabled", true)
    var after := await _capture(AFTER_PATH)
    if before == null or after == null:
        _fail("capture missing")
        return
    if before.get_width() != WIDTH or before.get_height() != HEIGHT or after.get_width() != WIDTH or after.get_height() != HEIGHT:
        _fail("capture resolution must be 1280x720")
        return

    var over3 := 0
    var over8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var total := WIDTH * HEIGHT
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r) * 255.0, maxf(absf(a.g - b.g) * 255.0, absf(a.b - b.b) * 255.0))
            if delta > 3.0:
                over3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    print("MIDI_OFFICIAL_PAVED_FORECOURT_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f bbox=%dx%d camera=%s fov=%.1f" % [over3, ratio3, over8, ratio8, bbox_width, bbox_height, str(CAMERA_POSITION), CAMERA_FOV])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("full-frame >3 RGB area below locked 3.0% anti-micro gate")
        return
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("full-frame >8 RGB area below locked 1.5% recognition gate")
        return
    if bbox_width < MIN_BBOX_WIDTH or bbox_height < MIN_BBOX_HEIGHT:
        _fail("changed region below locked 700x160 full-frame extent gate")
        return
    print("MIDI_OFFICIAL_PAVED_FORECOURT_WITNESS_OK human_full_frame_3_second_verdict=REQUIRED")
    quit(0)

func _dynamic_name(node_name: String) -> bool:
    var n := node_name.to_lower()
    for token: String in ["player", "npc", "pedestrian", "traffic", "vehicle", "movingcar", "ambient", "police"]:
        if n.contains(token):
            return true
    return false

func _freeze_and_mask_dynamics(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    if node is Node3D and _dynamic_name(str(node.name)):
        (node as Node3D).visible = false
        node.process_mode = Node.PROCESS_MODE_DISABLED
    for child: Node in node.get_children():
        _freeze_and_mask_dynamics(child)

func _capture(path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.save_png(path) != OK:
        return null
    return image

func _fail(message: String) -> void:
    push_error("MIDI_OFFICIAL_PAVED_FORECOURT_WITNESS_FAIL: " + message)
    quit(1)
