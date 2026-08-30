extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ZONE_ID := "midi_machine_labo"
const OUT_DIR := "res://artifacts/qa/midi_city_machine_post_integration_witness"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_CITY_MACHINE_POST_INTEGRATION_WITNESS_FAIL: %s" % message)
    quit(1)

func _zone_by_id(selector: Node) -> Dictionary:
    var rows: Variant = selector.call("available_zones")
    if not rows is Array:
        return {}
    for raw: Variant in rows as Array:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == ZONE_ID:
            return (raw as Dictionary).duplicate(true)
    return {}

func _capture(path: String) -> bool:
    for _i: int in range(3):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    return image.save_png(ProjectSettings.globalize_path(path)) == OK

func _camera(main: Node, position: Vector3, target: Vector3) -> Camera3D:
    var camera := Camera3D.new()
    camera.fov = 60.0
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

    var selector: Node = null
    var player: CharacterBody3D = null
    for _attempt: int in range(360):
        await process_frame
        selector = root.get_node_or_null("ZoneSelectorRuntime")
        if current_scene != null:
            player = current_scene.get_node_or_null("Player") as CharacterBody3D
        if selector != null and player != null:
            break
    if selector == null or player == null or current_scene == null:
        _fail("production runtime unavailable")
        return

    var zone := _zone_by_id(selector)
    if zone.is_empty() or str(zone.get("quality", "")) != "LABO":
        _fail("truthful LABO candidate unavailable")
        return
    await selector.call("_apply_zone", current_scene, zone)
    for _i: int in range(24):
        await process_frame

    var lab := current_scene.get_node_or_null("ZoneLab_%s" % ZONE_ID)
    if lab == null:
        _fail("candidate was not mounted through production selector")
        return
    var stats: Variant = lab.get("last_stats")
    if not stats is Dictionary:
        _fail("candidate stats unavailable")
        return
    if int((stats as Dictionary).get("buildings", 0)) <= 0 or int((stats as Dictionary).get("street_surfaces", 0)) <= 0:
        _fail("official geometry minimum not satisfied")
        return

    var reporter: Node = selector.call("reporting_runtime")
    if reporter == null:
        _fail("post-integration reporter missing")
        return
    var report_button := reporter.get_node_or_null("ReportButton") as Button
    if report_button == null or not report_button.text.begins_with("À SIGNALER"):
        _fail("À SIGNALER control not mounted")
        return

    var context: Variant = selector.call("current_report_context")
    if not context is Dictionary or str((context as Dictionary).get("id", "")) != ZONE_ID:
        _fail("candidate report context is not active-zone truth")
        return
    var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.25, 0.35, 0.45, 1.0))
    var visual_report_path := str(reporter.call("create_report_from_context", "post-integration witness", image, context as Dictionary, false))
    if visual_report_path.is_empty() or int(reporter.call("visual_report_count", ZONE_ID)) < 1:
        _fail("open visual report was not persisted")
        return
    if not bool(selector.call("can_promote_zone", ZONE_ID)):
        _fail("open visual report still blocks playable advancement")
        return

    player.velocity = Vector3.ZERO
    player.set_process(false)
    player.set_physics_process(false)
    var camera := _camera(current_scene, Vector3(-600.0, 68.0, 610.0), Vector3(-420.0, 6.0, 420.0))
    reporter.call("begin_report")
    await process_frame
    var review_panel := reporter.get_node_or_null("ReportPanel") as PanelContainer
    if review_panel == null or not review_panel.visible:
        _fail("post-integration review panel did not open")
        return
    for button_name: String in ["KeepVisualButton", "ImproveVisualButton", "RejectVisualButton", "SendVisualIssueButton"]:
        if reporter.find_child(button_name, true, false) == null:
            _fail("review action missing: %s" % button_name)
            return

    var arrival := OUT_DIR + "/playable_candidate_review_panel.png"
    if not await _capture(arrival):
        _fail("playable candidate review-panel capture failed")
        return
    camera.queue_free()
    await process_frame

    var report := {
        "format": "grand-bruxelles-midi-city-machine-post-integration-witness-v1",
        "zone_id": ZONE_ID,
        "stored_quality": "LABO",
        "playable_candidate_mounted": true,
        "post_integration_review_available": true,
        "review_panel_visible_in_capture": true,
        "review_actions_present": ["GARDER", "AMELIORER", "REJETER", "SIGNALER"],
        "open_visual_report_created": true,
        "open_visual_report_blocks_advancement": false,
        "hard_geometry_gate_passed": true,
        "resolution": [WIDTH, HEIGHT],
        "capture": arrival,
        "stats": (stats as Dictionary).duplicate(true),
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var handle := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/report.json"), FileAccess.WRITE)
    if handle == null:
        _fail("report.json unavailable")
        return
    handle.store_string(JSON.stringify(report, "  "))
    handle.close()
    print("MIDI_CITY_MACHINE_POST_INTEGRATION_WITNESS_OK: mounted=true panel=true visual_report_blocks=false hard_geometry=true")
    quit(0)
