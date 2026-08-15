extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 60
const BEFORE_PATH := "res://artifacts/visual/midi_arrival_planimetry_before.png"
const AFTER_PATH := "res://artifacts/visual/midi_arrival_planimetry_after.png"
const MIN_CHANGED_OVER_3 := 0.050
const MIN_CHANGED_OVER_8 := 0.020
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_ARRIVAL_PLANIMETRY_WITNESS_FAIL: " + message)
    quit(1)

func _hide_ui_and_player(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls", "WalletHud"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar", "PhysicalCarB"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false

func _is_dynamic_name(name_text: String) -> bool:
    var lowered := name_text.to_lower()
    for token in ["npc", "traffic", "vehicle", "car", "pedestrian", "agent", "urbanlife", "urban_life"]:
        if lowered.contains(token):
            return true
    return false

func _freeze_dynamic_recursive(node: Node) -> int:
    var frozen := 0
    for child in node.get_children():
        frozen += _freeze_dynamic_recursive(child)
    if node is CharacterBody3D or node is RigidBody3D or node is AnimatableBody3D or node is AnimationPlayer or _is_dynamic_name(node.name):
        node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is RigidBody3D:
            (node as RigidBody3D).freeze = true
        frozen += 1
    return frozen

func _capture(path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid: " + path)
        return null
    var absolute_output := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("capture save failed: " + path)
        return null
    return image

func _measure(before: Image, after: Image) -> Dictionary:
    var gt3 := 0
    var gt8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) * 255.0
            if delta > 3.0:
                gt3 += 1
                min_x = mini(min_x, x); min_y = mini(min_y, y); max_x = maxi(max_x, x); max_y = maxi(max_y, y)
            if delta > 8.0:
                gt8 += 1
    var total := WIDTH * HEIGHT
    return {"gt3":gt3,"gt8":gt8,"pct3":float(gt3)/float(total),"pct8":float(gt8)/float(total),"bbox":[min_x,min_y,max_x,max_y]}

func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    _hide_ui_and_player(scene)

    var existing_camera := root.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false
    var camera := Camera3D.new()
    camera.name = "MidiArrivalPlanimetryWitnessCamera"
    camera.position = ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 2.6, 0.0)
    camera.fov = 65.0
    scene.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 3.2, 0.0), Vector3.UP)
    camera.current = true

    var controller := root.get_node_or_null("MidiArrivalPlanimetry")
    if controller == null:
        _fail("autoload controller missing")
        return
    var attempts := 0
    while not bool(controller.get("visual_built")) and attempts < 60:
        await process_frame
        attempts += 1
    if not bool(controller.get("visual_built")):
        _fail("controller did not mount")
        return

    for _frame in range(WARMUP_FRAMES):
        await process_frame
    _hide_ui_and_player(scene)
    var frozen_count := _freeze_dynamic_recursive(scene)
    await process_frame

    controller.call("set_arrival_planimetry_enabled", false)
    var before := await _capture(BEFORE_PATH)
    if before == null:
        return
    controller.call("set_arrival_planimetry_enabled", true)
    var after := await _capture(AFTER_PATH)
    if after == null:
        return

    var metrics := _measure(before, after)
    print("MIDI_ARRIVAL_PLANIMETRY_METRICS gt3=%d pct3=%.6f gt8=%d pct8=%.6f bbox=%s frozen_same_scene=true frozen_dynamic_nodes=%d" % [metrics.gt3, metrics.pct3, metrics.gt8, metrics.pct8, str(metrics.bbox), frozen_count])
    if float(metrics.pct3) < MIN_CHANGED_OVER_3:
        _fail("normal-distance >3 RGB area below predeclared 5.0% gate")
        return
    if float(metrics.pct8) < MIN_CHANGED_OVER_8:
        _fail("normal-distance >8 RGB area below predeclared 2.0% gate")
        return
    print("MIDI_ARRIVAL_PLANIMETRY_WITNESS_OK before=%s after=%s camera=production_fonsny_28m fov=65 frozen_same_scene=true frozen_dynamic_nodes=%d" % [BEFORE_PATH, AFTER_PATH, frozen_count])
    quit(0)
