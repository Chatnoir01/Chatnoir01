extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const WIDTH := 1280
const HEIGHT := 720
const MIN_OVER3 := 0.05
const MIN_OVER8 := 0.02

const MIDI_ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const MIDI_ROAD_SIDE := Vector3(0.779, 0.0, 0.627)
const BOURSE_CAMERA_POSITION := Vector3(101.90921495304792, 1.68, -738.3896080011874)
const BOURSE_CAMERA_ROTATION := Vector3(0.0, -135.21993255901, 0.0)
const BOURSE_HORIZONTAL_FOV := 63.65489315334623

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OVERCAST_WITNESS_FAIL: %s" % message)
    quit(1)

func _horizontal_to_vertical_fov(horizontal_degrees: float, aspect: float) -> float:
    return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_degrees) * 0.5) / aspect))

func _freeze_dynamic(node: Node) -> void:
    if node is CharacterBody3D or node is RigidBody3D or node is VehicleBody3D:
        if node is Node3D:
            (node as Node3D).visible = false
        node.process_mode = Node.PROCESS_MODE_DISABLED
    if node is Label3D:
        (node as Label3D).visible = false
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    var lowered := node.name.to_lower()
    if "traffic" in lowered or "npc" in lowered or "urbanlife" in lowered:
        node.process_mode = Node.PROCESS_MODE_DISABLED
    for child: Node in node.get_children():
        _freeze_dynamic(child)

func _set_camera(camera: Camera3D, location: String) -> void:
    if location == "midi":
        camera.position = MIDI_ENTRANCE + MIDI_ROAD_SIDE * 28.0 + Vector3(0.0, 2.6, 0.0)
        camera.fov = 65.0
        camera.look_at(MIDI_ENTRANCE + Vector3(0.0, 2.0, 0.0), Vector3.UP)
    else:
        camera.position = BOURSE_CAMERA_POSITION
        camera.rotation_degrees = BOURSE_CAMERA_ROTATION
        camera.keep_aspect = Camera3D.KEEP_HEIGHT
        camera.fov = _horizontal_to_vertical_fov(BOURSE_HORIZONTAL_FOV, float(WIDTH) / float(HEIGHT))

func _save_frame(path: String) -> Image:
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return null
    if image.save_png(path) != OK:
        return null
    return image

func _measure(label: String, before: Image, after: Image) -> bool:
    var over3 := 0
    var over8 := 0
    var total := WIDTH * HEIGHT
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                over3 += 1
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("BRUSSELS_OVERCAST_%s_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f" % [label, over3, ratio3, over8, ratio8])
    if ratio3 < MIN_OVER3 or ratio8 < MIN_OVER8:
        _fail("%s atmosphere impact below declared normal-distance gate" % label)
        return false
    return true

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var world := packed.instantiate()
    if world == null:
        _fail("main scene failed to instantiate")
        return
    root.add_child(world)
    current_scene = world
    for _frame: int in range(12):
        await process_frame

    _freeze_dynamic(world)
    var existing := get_root().get_viewport().get_camera_3d()
    if existing != null:
        existing.current = false
    var camera := Camera3D.new()
    camera.name = "BrusselsOvercastWitnessCamera"
    world.add_child(camera)
    camera.current = true

    var atmosphere := root.get_node_or_null("BrusselsAtmosphere")
    if atmosphere == null or not atmosphere.has_method("set_profile_enabled"):
        _fail("runtime atmosphere autoload missing")
        return

    for location: String in ["midi", "bourse"]:
        _set_camera(camera, location)
        atmosphere.call("set_profile_enabled", false)
        var before: Image = await _save_frame(OUTPUT_DIR + "/brussels_overcast_%s_before.png" % location)
        atmosphere.call("set_profile_enabled", true)
        var after: Image = await _save_frame(OUTPUT_DIR + "/brussels_overcast_%s_after.png" % location)
        if before == null or after == null:
            _fail("%s deterministic capture missing" % location)
            return
        if not _measure(location.to_upper(), before, after):
            return

    print("BRUSSELS_OVERCAST_WITNESS_OK frozen_dynamic_state=true same_world_instance=true")
    quit(0)
