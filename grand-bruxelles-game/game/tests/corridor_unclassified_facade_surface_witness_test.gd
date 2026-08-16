extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/corridor_unclassified_facade_before.png"
const AFTER_PATH := OUTPUT_DIR + "/corridor_unclassified_facade_after.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.025
const MIN_CHANGED_OVER_8 := 0.008
const MIN_BUILDINGS := 40
const MIDI_ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    paused = false
    push_error("CORRIDOR_UNCLASSIFIED_FACADE_FAIL: " + message)
    quit(1)

func _capture(path: String) -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image.save_png(path) != OK:
        return null
    return image

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var world := packed.instantiate()
    get_root().add_child(world)

    var runtime := get_root().get_node_or_null("CorridorUnclassifiedFacadeSurfaceRuntime")
    if runtime == null:
        _fail("CorridorUnclassifiedFacadeSurfaceRuntime autoload missing")
        return
    for _i in range(120):
        if runtime.ready_complete():
            break
        await process_frame
    if not runtime.ready_complete():
        _fail("runtime did not discover generic OSM building surfaces")
        return
    if runtime.applied_surface_count() < MIN_BUILDINGS:
        _fail("shared surface must affect at least %d generic buildings, got %d" % [MIN_BUILDINGS, runtime.applied_surface_count()])
        return
    if runtime.shared_material_count() < 4:
        _fail("existing authored facade palette was collapsed")
        return
    if not runtime.geometry_contract_intact():
        _fail("surface treatment changed building geometry")
        return

    for record in runtime.target_records():
        var material := record.get("enhanced_material") as ShaderMaterial
        if material == null:
            _fail("enhanced building lacks ShaderMaterial")
            return
        if str(material.get_meta("material_family", "")) != "brussels_unclassified_facade_surface":
            _fail("material family metadata drifted")
            return
        if bool(material.get_meta("source_verified_material_identity", true)):
            _fail("unclassified OSM buildings must not claim exact brick/stone/concrete identity")
            return
        if not bool(material.get_meta("presentation_only", false)):
            _fail("unclassified finish must remain presentation-only")
            return
        if bool(material.get_meta("geometry_changed", true)) or bool(material.get_meta("masonry_pattern_authored", true)):
            _fail("surface pass must not invent geometry or masonry units")
            return

    var camera := Camera3D.new()
    camera.name = "CorridorUnclassifiedFacadeWitnessCamera"
    camera.position = MIDI_ENTRANCE + ROAD_SIDE * 32.0 + Vector3(0.0, 3.0, 0.0)
    camera.fov = 67.0
    world.add_child(camera)
    camera.look_at(MIDI_ENTRANCE + Vector3(0.0, 8.0, 0.0), Vector3.UP)
    camera.current = true

    paused = true
    runtime.set_enhanced_surface_enabled(false)
    var before := await _capture(BEFORE_PATH)
    runtime.set_enhanced_surface_enabled(true)
    var after := await _capture(AFTER_PATH)
    paused = false
    if before == null or after == null:
        _fail("capture missing")
        return
    if before.get_width() != WIDTH or before.get_height() != HEIGHT or after.get_width() != WIDTH or after.get_height() != HEIGHT:
        _fail("capture resolution must be 1280x720")
        return

    var over3 := 0
    var over8 := 0
    var min_x := WIDTH
    var max_x := -1
    var min_y := HEIGHT
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
                max_x = maxi(max_x, x)
                min_y = mini(min_y, y)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    var bbox_w := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_h := 0 if max_y < min_y else max_y - min_y + 1
    print("CORRIDOR_UNCLASSIFIED_FACADE_DELTA surfaces=%d materials=%d over3=%d ratio3=%.6f over8=%d ratio8=%.6f bbox=%dx%d" % [runtime.applied_surface_count(), runtime.shared_material_count(), over3, ratio3, over8, ratio8, bbox_w, bbox_h])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("normal-player >3 RGB area below 2.50% anti-micro gate")
        return
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("normal-player >8 RGB area below 0.80% recognition gate")
        return
    if bbox_w < 500 or bbox_h < 180:
        _fail("surface response is too localized in the player frame")
        return
    print("CORRIDOR_UNCLASSIFIED_FACADE_OK")
    quit(0)
