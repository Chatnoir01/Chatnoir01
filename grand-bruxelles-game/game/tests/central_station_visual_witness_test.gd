extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ZONE_ID := "central"
const OUT_DIR := "res://artifacts/qa/central_station_visual_witness"
const WIDTH := 1280
const HEIGHT := 720
const REVIEW_ANCHOR := Vector3(647.68, 0.0, -407.70)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CENTRAL_STATION_VISUAL_WITNESS_FAIL: %s" % message)
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

func _set_canvas_items_visible(node: Node, visible: bool) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = visible
    elif node is CanvasItem:
        (node as CanvasItem).visible = visible
    for child: Node in node.get_children():
        _set_canvas_items_visible(child, visible)

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
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    return image.save_png(ProjectSettings.globalize_path(path)) == OK

func _install_review_overlay(main: Node) -> void:
    var overlay := CanvasLayer.new()
    overlay.name = "CentralStationWitnessOverlay"
    overlay.layer = 250
    var panel := ColorRect.new()
    panel.position = Vector2(18.0, 18.0)
    panel.size = Vector2(880.0, 56.0)
    panel.color = Color(0.02, 0.02, 0.02, 0.84)
    overlay.add_child(panel)
    var label := Label.new()
    label.position = Vector2(34.0, 30.0)
    label.text = "CENTRAL — URBAN 30201 LABO_BRUT | NON-AUTHORITATIVE ALIGNMENT | JOUABLE=false"
    label.add_theme_font_size_override("font_size", 17)
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
    if current_scene == null or player == null or selector == null:
        _fail("production main/player/selector unavailable")
        return
    var zone := _zone_by_id(selector, ZONE_ID)
    if zone.is_empty() or str(zone.get("quality", "")) != "LABO_BRUT" or str(zone.get("mode", "")) != "script_zone":
        _fail("Central LABO_BRUT selector contract missing")
        return
    var toggle := selector.get_node_or_null("ZoneSelectorToggle") as Button
    if toggle == null or toggle.text != "CHANGER DE ZONE" or not toggle.is_visible_in_tree():
        _fail("production CHANGER DE ZONE control is not player-visible")
        return
    await selector.call("_apply_zone", current_scene, zone)
    await _wait_frames(24)
    var lab := current_scene.get_node_or_null("ZoneLab_%s" % ZONE_ID)
    if lab == null:
        _fail("production selector did not mount Central LABO_BRUT")
        return
    var stats: Variant = lab.get("last_stats")
    if not stats is Dictionary:
        _fail("Central LABO runtime stats unavailable")
        return
    var building_count := int((stats as Dictionary).get("buildings", 0))
    var street_surface_count := int((stats as Dictionary).get("street_surfaces", 0))
    var bay_count := int((stats as Dictionary).get("upper_bays", 0))
    var column_count := int((stats as Dictionary).get("entrance_columns", 0))
    if building_count != 1 or street_surface_count != 1 or bay_count != 9 or column_count != 4:
        _fail("Central source-backed review invariants are incomplete")
        return
    var station: Node3D = lab.get_node_or_null("CentralStationUrban30201") as Node3D
    if station == null or int(station.get_meta("source_urban_id", -1)) != 30201:
        _fail("Urban 30201 station root unavailable")
        return
    if bool(station.get_meta("authoritative_urbis_alignment", true)) or bool(station.get_meta("promotion_allowed", true)):
        _fail("review geometry truth contract drifted")
        return
    if str(current_scene.get_meta("grand_bruxelles_active_zone_id", "")) != ZONE_ID:
        _fail("active-zone truth was not published for Central")
        return

    player.velocity = Vector3.ZERO
    player.set_process(false)
    player.set_physics_process(false)
    _hide_canvas(root)
    _install_review_overlay(current_scene)
    var arrival_position := Vector3(REVIEW_ANCHOR.x, 5.2, REVIEW_ANCHOR.z + 36.0)
    var facade_target := Vector3(REVIEW_ANCHOR.x, 8.8, REVIEW_ANCHOR.z + 1.5)
    var arrival_camera := _configure_review_camera(current_scene, "CentralStationArrivalWitnessCamera", arrival_position, facade_target, 58.0)
    var arrival_path := OUT_DIR + "/central_station_arrival.png"
    if not await _capture(arrival_path):
        _fail("arrival capture failed")
        return
    arrival_camera.queue_free()
    await process_frame
    var overview_position := Vector3(REVIEW_ANCHOR.x + 48.0, 31.0, REVIEW_ANCHOR.z + 49.0)
    var overview_target := Vector3(REVIEW_ANCHOR.x, 8.0, REVIEW_ANCHOR.z - 5.0)
    var overview_camera := _configure_review_camera(current_scene, "CentralStationOverviewWitnessCamera", overview_position, overview_target, 56.0)
    var overview_path := OUT_DIR + "/central_station_overview.png"
    if not await _capture(overview_path):
        _fail("overview capture failed")
        return
    overview_camera.queue_free()
    await process_frame

    var overlay := current_scene.get_node_or_null("CentralStationWitnessOverlay")
    if overlay != null:
        overlay.queue_free()
    _set_canvas_items_visible(selector, true)
    selector.call("set_menu_open", false)
    await _wait_frames(3)
    toggle = selector.get_node_or_null("ZoneSelectorToggle") as Button
    var panel := selector.get_node_or_null("ZoneSelectorPanel") as PanelContainer
    if toggle == null or toggle.text != "CHANGER DE ZONE" or not toggle.is_visible_in_tree() or panel == null:
        _fail("production CHANGER DE ZONE control disappeared after Central activation")
        return
    toggle.emit_signal("pressed")
    await _wait_frames(2)
    var central_button := panel.find_child("Zone_central", true, false) as Button
    if not panel.visible or central_button == null or not central_button.is_visible_in_tree() or not central_button.text.contains("LABO_BRUT"):
        _fail("CHANGER DE ZONE did not expose Central LABO_BRUT")
        return
    var ui_path := OUT_DIR + "/central_station_change_zone_button.png"
    if not await _capture(ui_path):
        _fail("change-zone UI witness capture failed")
        return

    var report := {
        "format": "grand-bruxelles-central-station-visual-witness-v2",
        "zone_id": ZONE_ID,
        "urban_id": 30201,
        "quality": "LABO_BRUT",
        "jouable": false,
        "human_review_required": true,
        "promotion_performed": false,
        "authoritative_urbis_alignment": false,
        "temporary_review_anchor": [REVIEW_ANCHOR.x, REVIEW_ANCHOR.y, REVIEW_ANCHOR.z],
        "resolution": [WIDTH, HEIGHT],
        "arrival_capture": arrival_path,
        "overview_capture": overview_path,
        "change_zone_ui_capture": ui_path,
        "change_zone_button": {"text": toggle.text, "visible_in_tree": toggle.is_visible_in_tree(), "panel_opened": panel.visible},
        "stats": (stats as Dictionary).duplicate(true),
        "production_selector_path": true,
        "source_backed_visual_invariants": {"upper_bays": 9, "entrance_columns": 4, "bilingual_signage": true, "canopy": true}
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var report_file := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/report.json"), FileAccess.WRITE)
    if report_file == null:
        _fail("report.json could not be opened")
        return
    report_file.store_string(JSON.stringify(report, "  "))
    report_file.close()
    print("CENTRAL_STATION_VISUAL_WITNESS_OK: urban_id=30201 quality=LABO_BRUT buildings=%d surfaces=%d bays=%d columns=%d captures=3 change_zone_button=true panel_opened=true authoritative_urbis=false promotion=false" % [building_count, street_surface_count, bay_count, column_count])
    quit(0)