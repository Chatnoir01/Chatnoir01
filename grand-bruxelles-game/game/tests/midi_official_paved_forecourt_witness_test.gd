extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_official_paved_forecourt_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_official_paved_forecourt_after.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.010
const MIN_CHANGED_OVER_8 := 0.0035

# Same Midi arrival anchor family already used by production material witnesses.
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)

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
    await process_frame
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

    var camera := Camera3D.new()
    camera.name = "MidiOfficialPavedForecourtWitnessCamera"
    camera.position = ENTRANCE + ROAD_SIDE * 25.0 + Vector3(0.0, 4.2, 0.0)
    camera.fov = 68.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 0.45, 0.0), Vector3.UP)
    camera.current = true

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
    var total := WIDTH * HEIGHT
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r) * 255.0, maxf(absf(a.g - b.g) * 255.0, absf(a.b - b.b) * 255.0))
            if delta > 3.0:
                over3 += 1
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("MIDI_OFFICIAL_PAVED_FORECOURT_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f" % [over3, ratio3, over8, ratio8])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("full-frame >3 RGB area below predeclared 1.0% anti-micro gate")
        return
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("full-frame >8 RGB area below predeclared 0.35% recognition gate")
        return
    print("MIDI_OFFICIAL_PAVED_FORECOURT_WITNESS_OK")
    quit(0)

func _freeze_and_mask_dynamics(node: Node) -> void:
    for child in node.get_children():
        var child_node := child as Node
        if child_node == null:
            continue
        var lower_name := String(child_node.name).to_lower()
        if child_node is Control:
            (child_node as Control).visible = false
        if child_node is Node3D and ("npc" in lower_name or "vehicle" in lower_name or "traffic" in lower_name or "police" in lower_name):
            (child_node as Node3D).visible = false
            child_node.process_mode = Node.PROCESS_MODE_DISABLED
        _freeze_and_mask_dynamics(child_node)

func _capture(path: String) -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image.save_png(path) != OK:
        return null
    return image

func _fail(message: String) -> void:
    push_error("MIDI_OFFICIAL_PAVED_FORECOURT_WITNESS_FAIL: " + message)
    quit(1)
