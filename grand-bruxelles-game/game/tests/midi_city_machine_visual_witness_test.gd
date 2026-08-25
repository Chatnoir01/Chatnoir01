extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ZONE_ID := "midi_machine_labo"
const CANONICAL_ZONE_ID := "midi"
const OUT_DIR := "res://artifacts/qa/midi_city_machine_visual_witness"
const WIDTH := 1280
const HEIGHT := 720


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MIDI_CITY_MACHINE_VISUAL_WITNESS_FAIL: %s" % message)
    quit(1)


func _wait_frames(count: int) -> void:
    for _i: int in range(count):
        await process_frame


func _hide_canvas(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    elif node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _hide_canvas(child)


func _zone_by_id(selector: Node, zone_id: String) -> Dictionary:
    var rows: Variant = selector.call("available_zones")
    if not rows is Array:
        return {}
    for raw: Variant in rows as Array:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == zone_id:
            return (raw as Dictionary).duplicate(true)
    return {}


func _capture(path: String) -> bool:
    for _frame: int in range(3):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        return false
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    return image.save_png(ProjectSettings.globalize_path(path)) == OK


func _install_review_overlay(main: Node) -> void:
    var overlay := CanvasLayer.new()
    overlay.name = "MidiCityMachineWitnessOverlay"
    overlay.layer = 250
    var panel := ColorRect.new()
    panel.position = Vector2(18.0, 18.0)
    panel.size = Vector2(690.0, 54.0)
    panel.color = Color(0.02, 0.02, 0.02, 0.82)
    overlay.add_child(panel)
    var label := Label.new()
    label.position = Vector2(34.0, 30.0)
    label.text = "MIDI — CITY MACHINE LABO  |  HUMAN REVIEW WITNESS  |  JOUABLE=false"
    label.add_theme_font_size_override("font_size", 18)
    overlay.add_child(label)
    main.add_child(overlay)


func _configure_review_camera(main: Node, name: String, position: Vector3, target: Vector3, fov: float) -> Camera3D:
    var camera := Camera3D.new()
    camera.name = name
    camera.fov = fov
    camera.near = 0.1
    camera.far = 4000.0
    main.add_child(camera)
    camera.global_position = position
    camera.look_at(target, Vector3.UP)
    camera.current = true
    return camera


func _run() -> void:
    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return

    var player: CharacterBody3D = null
    var selector: Node = null
    for _attempt: int in range(360):
        await process_frame
        if current_scene != null:
            player = current_scene.get_node_or_null("Player") as CharacterBody3D
        selector = root.get_node_or_null("ZoneSelectorRuntime")
        if player != null and selector != null:
            break
    if current_scene == null or player == null:
        _fail("production main/player unavailable")
        return
    if selector == null:
        _fail("ZoneSelectorRuntime autoload unavailable")
        return

    var zone := _zone_by_id(selector, ZONE_ID)
    if zone.is_empty():
        _fail("Midi City Machine LABO is not listed by the production selector")
        return
    if str(zone.get("quality", "")) != "LABO":
        _fail("review zone lost LABO quality")
        return
    if str(zone.get("review_alias_of", "")) != CANONICAL_ZONE_ID:
        _fail("review alias no longer points to canonical Midi")
        return
    if str(zone.get("mode", "")) != "script_zone":
        _fail("review zone no longer uses script_zone runtime")
        return

    await selector.call("_apply_zone", current_scene, zone)
    await _wait_frames(24)

    var lab := current_scene.get_node_or_null("ZoneLab_%s" % ZONE_ID)
    if lab == null:
        _fail("production selector did not mount Midi City Machine LABO")
        return
    var stats: Variant = lab.get("last_stats")
    if not stats is Dictionary:
        _fail("LABO runtime stats unavailable")
        return
    var building_count := int((stats as Dictionary).get("buildings", 0))
    var street_surface_count := int((stats as Dictionary).get("street_surfaces", 0))
    if building_count <= 0 or street_surface_count <= 0:
        _fail("LABO mounted without required official geometry")
        return

    if str(current_scene.get_meta("grand_bruxelles_active_zone_id", "")) != ZONE_ID:
        _fail("active-zone truth was not published for the review alias")
        return
    if str(current_scene.get_meta("grand_bruxelles_active_zone_label", "")) != "Midi — City Machine LABO":
        _fail("active-zone label does not identify the review candidate")
        return

    player.velocity = Vector3.ZERO
    player.set_process(false)
    player.set_physics_process(false)
    # Hide every production CanvasLayer, including autoload UI outside current_scene,
    # then add only the explicit review-truth overlay back on top.
    _hide_canvas(root)
    _install_review_overlay(current_scene)

    # The catalog spawn is intentionally near the regional edge. A literal eye-level
    # camera can land inside a source-backed building footprint, which is a bad human
    # witness even though the runtime is valid. Keep the camera above the same arrival
    # sector and look inward so the user can actually judge the generated geometry.
    var arrival_camera := _configure_review_camera(
        current_scene,
        "MidiCityMachineArrivalWitnessCamera",
        Vector3(-600.0, 68.0, 610.0),
        Vector3(-420.0, 6.0, 420.0),
        62.0
    )
    var arrival_path := OUT_DIR + "/midi_city_machine_arrival.png"
    if not await _capture(arrival_path):
        _fail("arrival capture failed")
        return

    arrival_camera.queue_free()
    await process_frame
    var overview_camera := _configure_review_camera(
        current_scene,
        "MidiCityMachineOverviewWitnessCamera",
        Vector3(0.0, 360.0, 760.0),
        Vector3(0.0, 0.0, 0.0),
        52.0
    )
    var overview_path := OUT_DIR + "/midi_city_machine_overview.png"
    if not await _capture(overview_path):
        _fail("overview capture failed")
        return

    var report := {
        "format": "grand-bruxelles-midi-city-machine-visual-witness-v1",
        "zone_id": ZONE_ID,
        "review_alias_of": CANONICAL_ZONE_ID,
        "quality": "LABO",
        "jouable": false,
        "human_review_required": true,
        "resolution": [WIDTH, HEIGHT],
        "arrival_capture": arrival_path,
        "overview_capture": overview_path,
        "arrival_camera": {"position": [-600.0, 68.0, 610.0], "target": [-420.0, 6.0, 420.0]},
        "stats": (stats as Dictionary).duplicate(true),
        "official_geometry_present": building_count > 0 and street_surface_count > 0,
        "production_selector_path": true,
        "production_ui_hidden_for_review_capture": true,
        "promotion_performed": false,
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var report_file := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/report.json"), FileAccess.WRITE)
    if report_file == null:
        _fail("report.json could not be opened")
        return
    report_file.store_string(JSON.stringify(report, "  "))
    report_file.close()

    print("MIDI_CITY_MACHINE_VISUAL_WITNESS_OK: zone=%s buildings=%d street_surfaces=%d captures=2 human_review_required=true promotion=false" % [ZONE_ID, building_count, street_surface_count])
    quit(0)
