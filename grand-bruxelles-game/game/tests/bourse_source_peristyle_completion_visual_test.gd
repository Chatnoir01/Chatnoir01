extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const CANDIDATE_PATH := "res://data/qa/bourse_portico_articulation_candidate.json"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/bourse_before_missing_fronton.png"
const AFTER_PATH := OUTPUT_DIR + "/bourse_after_source_fronton.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_FRACTION := 0.005
const MAX_CHANGED_FRACTION := 0.20

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_SOURCE_PERISTYLE_FAIL: " + message)
    quit(1)

func _vec2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
        return Vector2.ZERO
    return Vector2(float(raw[0]), float(raw[1]))

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

    # Freeze/mask dynamic world state before insertion. The visual delta must be
    # architectural only: no traffic, pedestrians, police, or shifting HUD state.
    var traffic := world.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
    for dynamic_name in ["MidiUrbanLife", "TrafficManager", "NpcPopulationDirector", "PoliceManager"]:
        var dynamic_node := world.get_node_or_null(dynamic_name)
        if dynamic_node != null:
            dynamic_node.process_mode = Node.PROCESS_MODE_DISABLED
            if dynamic_node is Node3D:
                (dynamic_node as Node3D).visible = false
    for ui_node in world.find_children("*", "CanvasLayer", true, false):
        if ui_node is CanvasLayer:
            (ui_node as CanvasLayer).visible = false

    root.add_child(world)
    await process_frame
    await process_frame

    var portico := world.get_node_or_null("BoursePorticoArticulation") as Node3D
    if portico == null:
        _fail("production Bourse portico missing")
        return
    if int(portico.get_meta("column_count", 0)) != 6:
        _fail("outer six-column source contract regressed")
        return
    if int(portico.get_meta("source_inner_column_count", 0)) != 2:
        _fail("heritage two-column inner peristyle missing")
        return
    if int(portico.get_meta("source_pediment_count", 0)) != 1:
        _fail("heritage triangular pediment missing")
        return
    if not bool(portico.get_meta("source_semantics_completed", false)):
        _fail("source semantic completion metadata missing")
        return
    var pediment := portico.get_node_or_null("SourceTriangularPediment") as MeshInstance3D
    if pediment == null or pediment.mesh == null:
        _fail("source pediment mesh missing")
        return
    if bool(pediment.get_meta("sculptural_relief_authored", true)):
        _fail("test forbids invented sculptural relief")
        return
    if not bool(pediment.get_meta("bounded_by_authoritative_front_envelope", false)):
        _fail("pediment must remain inside authoritative envelope")
        return

    var source_nodes := get_nodes_in_group("bourse_source_semantic_completion")
    if source_nodes.size() != 7:
        _fail("expected one pediment plus six pieces for two inner columns, got %d" % source_nodes.size())
        return

    if not FileAccess.file_exists(CANDIDATE_PATH):
        _fail("candidate source envelope missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("candidate source envelope invalid")
        return
    var data := parsed as Dictionary
    var envelope: Dictionary = data.get("authoritative_front_envelope", {})
    var plane_xz := _vec2(envelope.get("plane_point_game_x_z", []))
    var forward_xz := _vec2(envelope.get("toward_camera_x_z", []))
    var tangent_xz := _vec2(envelope.get("tangent_x_z", []))
    var toward_camera := Vector3(forward_xz.x, 0.0, forward_xz.y).normalized()
    var tangent := Vector3(tangent_xz.x, 0.0, tangent_xz.y).normalized()
    var t_min := float(envelope.get("tangent_min_m", 0.0))
    var t_max := float(envelope.get("tangent_max_m", 0.0))
    var front_mid_t := (t_min + t_max) * 0.5
    var plane := Vector3(plane_xz.x, 0.0, plane_xz.y)
    var front_center := plane + tangent * front_mid_t

    # Source-aligned boulevard exposure. It is derived from the same authoritative
    # plane and toward-camera basis as the architecture, not hand-tuned to crop
    # the new geometry into an artificial close-up.
    var camera := Camera3D.new()
    camera.name = "BourseSourcePeristyleWitnessCamera"
    camera.position = front_center + toward_camera * 54.0 - tangent * 6.0 + Vector3(0.0, 10.5, 0.0)
    camera.fov = 52.0
    world.add_child(camera)
    camera.look_at(front_center + Vector3(0.0, 11.5, 0.0), Vector3.UP)
    camera.current = true

    paused = true
    _set_source_completion_visible(source_nodes, false)
    var before := await _capture(BEFORE_PATH)
    _set_source_completion_visible(source_nodes, true)
    var after := await _capture(AFTER_PATH)
    if before == null or after == null:
        _fail("full-frame A/B capture missing")
        return
    if before.get_size() != Vector2i(WIDTH, HEIGHT) or after.get_size() != Vector2i(WIDTH, HEIGHT):
        _fail("A/B must match the production 1280x720 viewport")
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
    print("BOURSE_SOURCE_PERISTYLE_METRICS: gt8=%.3f%% bbox=%dx%d inner_columns=2 pediment=1" % [changed_fraction * 100.0, bbox_width, bbox_height])
    if changed_fraction < MIN_CHANGED_FRACTION:
        _fail("source completion is not materially visible in the boulevard full frame")
        return
    if changed_fraction > MAX_CHANGED_FRACTION:
        _fail("A/B changed too much of the frame; isolation or placement is suspect")
        return
    if bbox_width < 300 or bbox_height < 90:
        _fail("source completion is too localized for a 3-second silhouette giveaway")
        return

    print("BOURSE_SOURCE_PERISTYLE_OK: %s %s" % [BEFORE_PATH, AFTER_PATH])
    paused = false
    quit(0)

func _set_source_completion_visible(nodes: Array[Node], visible_value: bool) -> void:
    for node in nodes:
        if node is Node3D:
            (node as Node3D).visible = visible_value

func _capture(path: String) -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.save_png(path) != OK:
        return null
    return image
