extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_fonsny_depth_before_41m.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_fonsny_depth_after_14m.png"
const WIDTH := 1280
const HEIGHT := 720
const SOURCE_DEPTH_M := 14.0
const LEGACY_DEPTH_M := 41.0
const MIN_CHANGED_FRACTION := 0.01
const MAX_CHANGED_FRACTION := 0.35
const MIDI_FONSNY_AXIS := Vector3(-0.627, 0.0, 0.779)
const MIDI_ROAD_SIDE := Vector3(0.779, 0.0, 0.627)
const BLOCK_NAMES := ["FonsnyWingSouth", "FonsnyCentral", "FonsnyWingNorth"]

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_DEPTH_WITNESS_FAIL: " + message)
    quit(1)

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var world := packed.instantiate()
    if world == null:
        _fail("production main scene did not instantiate")
        return

    # Freeze/mask dynamic state before the production tree enters the scene so
    # the A/B changes geometry only, never pedestrian/traffic placement.
    var traffic := world.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
    for dynamic_name in ["MidiUrbanLife", "TrafficManager", "PoliceManager"]:
        var dynamic_node := world.get_node_or_null(dynamic_name)
        if dynamic_node != null:
            dynamic_node.process_mode = Node.PROCESS_MODE_DISABLED
            if dynamic_node is Node3D:
                (dynamic_node as Node3D).visible = false

    root.add_child(world)
    await process_frame
    await process_frame

    var station := world.get_node_or_null("MidiHeroZone/BruxellesMidiStation") as Node3D
    if station == null:
        _fail("Midi station hero geometry missing")
        return

    for block_name in BLOCK_NAMES:
        var block := station.get_node_or_null(block_name) as Node3D
        if block == null:
            _fail("office block missing: " + block_name)
            return
        var base := block.get_node_or_null("BlueStoneBase") as MeshInstance3D
        var brick := block.get_node_or_null("FauquenbergBrick") as MeshInstance3D
        var roof := block.get_node_or_null("FlatRoof") as MeshInstance3D
        var band := block.get_node_or_null("HorizontalBand_00") as MeshInstance3D
        if base == null or brick == null or roof == null or band == null:
            _fail("office mass/facade contract incomplete: " + block_name)
            return
        var base_box := base.mesh as BoxMesh
        var brick_box := brick.mesh as BoxMesh
        var roof_box := roof.mesh as BoxMesh
        if base_box == null or brick_box == null or roof_box == null:
            _fail("office mass must remain BoxMesh geometry: " + block_name)
            return
        if absf(base_box.size.x - SOURCE_DEPTH_M) > 0.001 or absf(brick_box.size.x - SOURCE_DEPTH_M) > 0.001:
            _fail("source-backed office depth is not 14 m: " + block_name)
            return
        if absf(roof_box.size.x - (SOURCE_DEPTH_M + 1.1)) > 0.001:
            _fail("roof no longer follows corrected office depth: " + block_name)
            return
        if absf(base.position.x - 13.5) > 0.001 or absf(brick.position.x - 13.5) > 0.001:
            _fail("rail-side trim must preserve the Avenue Fonsny facade plane: " + block_name)
            return
        if absf(band.position.x - 20.57) > 0.001:
            _fail("street-facing facade plane moved: " + block_name)
            return
        if absf(float(block.get_meta("source_site_depth_m", 0.0)) - SOURCE_DEPTH_M) > 0.001:
            _fail("source depth metadata missing: " + block_name)
            return
        if not bool(block.get_meta("street_facade_plane_preserved", false)):
            _fail("facade-plane preservation metadata missing: " + block_name)
            return

    var camera := Camera3D.new()
    camera.name = "MidiFonsnyDepthWitnessCamera"
    var target := station.global_position + Vector3(0.0, 10.0, 0.0)
    camera.position = station.global_position + MIDI_ROAD_SIDE * 90.0 + MIDI_FONSNY_AXIS * -55.0 + Vector3(0.0, 13.0, 0.0)
    camera.fov = 58.0
    world.add_child(camera)
    camera.look_at(target, Vector3.UP)
    camera.current = true

    paused = true
    _set_office_depth(station, LEGACY_DEPTH_M)
    var before := await _capture(BEFORE_PATH)
    _set_office_depth(station, SOURCE_DEPTH_M)
    var after := await _capture(AFTER_PATH)
    if before == null or after == null:
        _fail("A/B capture missing")
        return
    if before.get_size() != Vector2i(WIDTH, HEIGHT) or after.get_size() != Vector2i(WIDTH, HEIGHT):
        _fail("A/B capture resolution must be 1280x720")
        return

    var changed := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta > 8.0 / 255.0:
                changed += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)

    var changed_fraction := float(changed) / float(WIDTH * HEIGHT)
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    var depth_reduction := 1.0 - SOURCE_DEPTH_M / LEGACY_DEPTH_M
    print("MIDI_FONSNY_DEPTH_WITNESS_METRICS: depth=%.1f->%.1fm reduction=%.2f%% gt8=%.3f%% bbox=%dx%d" % [LEGACY_DEPTH_M, SOURCE_DEPTH_M, depth_reduction * 100.0, changed_fraction * 100.0, bbox_width, bbox_height])
    if changed_fraction < MIN_CHANGED_FRACTION:
        _fail("source-backed massing correction is not materially visible")
        return
    if changed_fraction > MAX_CHANGED_FRACTION:
        _fail("A/B changed too much of the full frame; dynamic-state isolation failed")
        return
    if bbox_width < 220 or bbox_height < 100:
        _fail("massing correction is too localized for a 3-second giveaway")
        return

    print("MIDI_FONSNY_DEPTH_WITNESS_OK: %s %s" % [BEFORE_PATH, AFTER_PATH])
    paused = false
    quit(0)

func _set_office_depth(station: Node3D, target_depth: float) -> void:
    for block_name in BLOCK_NAMES:
        var block := station.get_node(block_name) as Node3D
        var base := block.get_node("BlueStoneBase") as MeshInstance3D
        var brick := block.get_node("FauquenbergBrick") as MeshInstance3D
        var roof := block.get_node("FlatRoof") as MeshInstance3D
        var base_box := base.mesh as BoxMesh
        var brick_box := brick.mesh as BoxMesh
        var roof_box := roof.mesh as BoxMesh
        var current_depth := base_box.size.x
        var centre_delta := (current_depth - target_depth) * 0.5
        base_box.size.x = target_depth
        brick_box.size.x = target_depth
        roof_box.size.x = target_depth + 1.1
        base.position.x += centre_delta
        brick.position.x += centre_delta
        roof.position.x += centre_delta

func _capture(path: String) -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.save_png(path) != OK:
        return null
    return image
