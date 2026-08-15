extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_fonsny_modernist_register_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_fonsny_modernist_register_after.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_RATIO_OVER_3 := 0.030
const MIN_RATIO_OVER_8 := 0.010
const MIN_BBOX_WIDTH := 420
const MIN_BBOX_HEIGHT := 220

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var world := packed.instantiate()
    get_root().add_child(world)
    await process_frame
    await process_frame

    var central := world.get_node_or_null("MidiHeroZone/BruxellesMidiStation/FonsnyCentral") as Node3D
    if central == null:
        _fail("FonsnyCentral missing")
        return
    var registers := _collect_registers(world)
    if registers.size() != 3:
        _fail("expected three modernist facade registers")
        return

    var camera := Camera3D.new()
    camera.name = "MidiFonsnyRegisterWitnessCamera"
    var outward := central.global_transform.basis.x.normalized()
    camera.position = central.global_position + outward * 34.0 + Vector3(0.0, 1.72, 0.0)
    camera.fov = 65.0
    world.add_child(camera)
    camera.look_at(central.global_position + Vector3(0.0, 10.0, 0.0), Vector3.UP)
    camera.current = true
    await process_frame

    # Freeze the entire authored/dynamic world. A/B changes only register visibility,
    # so vehicles, PNJs and physics cannot contaminate the pixel delta.
    world.process_mode = Node.PROCESS_MODE_DISABLED
    for register in registers:
        register.visible = false
    var before := await _capture(BEFORE_PATH)
    for register in registers:
        register.visible = true
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
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                over3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                over8 += 1

    var total := WIDTH * HEIGHT
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    print("MIDI_FONSNY_REGISTER_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f bbox=%dx%d" % [over3, ratio3, over8, ratio8, bbox_width, bbox_height])
    if ratio3 < MIN_RATIO_OVER_3:
        _fail("full-frame >3 RGB impact below 3.0%")
        return
    if ratio8 < MIN_RATIO_OVER_8:
        _fail("full-frame >8 RGB impact below 1.0%")
        return
    if bbox_width < MIN_BBOX_WIDTH or bbox_height < MIN_BBOX_HEIGHT:
        _fail("change is too localized for a broad frontage correction")
        return

    print("MIDI_FONSNY_REGISTER_WITNESS_OK")
    world.queue_free()
    await process_frame
    quit(0)

func _collect_registers(world: Node) -> Array[Node3D]:
    var result: Array[Node3D] = []
    for block_name: String in ["FonsnyWingSouth", "FonsnyCentral", "FonsnyWingNorth"]:
        var register := world.get_node_or_null("MidiHeroZone/BruxellesMidiStation/%s/ModernistFacadeRegister" % block_name) as Node3D
        if register != null:
            result.append(register)
    return result

func _capture(path: String) -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image.save_png(path) != OK:
        return null
    return image

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_REGISTER_WITNESS_FAIL: " + message)
    quit(1)
