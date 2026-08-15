extends SceneTree

const CONTROLLER := preload("res://game/scripts/location_label_controller.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_LOCATION_IDENTITY_BANNER_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var label := CONTROLLER.new()
    label.size = Vector2(496.0, 28.0)
    root.add_child(label)
    await process_frame

    var panel := label.get_identity_panel()
    if panel == null:
        _fail("identity panel missing")
        return
    if not panel.visible:
        _fail("identity panel not enabled by default")
        return
    if panel.z_index != -1:
        _fail("identity panel must render behind location text")
        return
    if absf(panel.offset_left + 8.0) > 0.001 or absf(panel.offset_top + 3.0) > 0.001:
        _fail("identity panel envelope drifted")
        return
    if absf(panel.offset_right - 6.0) > 0.001 or absf(panel.offset_bottom - 1.0) > 0.001:
        _fail("identity panel envelope drifted")
        return

    var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
    if style == null:
        _fail("identity panel style missing")
        return
    if style.bg_color.a < 0.90:
        _fail("identity panel must remain legible without emission")
        return
    if style.border_width_left != 1 or style.border_width_top != 1 or style.border_width_right != 1 or style.border_width_bottom != 1:
        _fail("identity border contract drifted")
        return

    if label.label_for_world_position(Vector3(-668.5, 0.0, 627.84)) != "BRUXELLES-MIDI · BRUSSEL-ZUID":
        _fail("Midi bilingual identity drifted")
        return
    if label.label_for_world_position(Vector3(81.54, 0.0, -664.58)) != "BOURSE · BEURS":
        _fail("Bourse bilingual identity drifted")
        return
    if label.label_for_world_position(Vector3(319.01, 0.0, -535.20)) != "GRAND-PLACE · GROTE MARKT":
        _fail("Grand-Place bilingual identity drifted")
        return
    if label.label_for_world_position(Vector3(5000.0, 0.0, 5000.0)) != "BRUXELLES · BRUSSEL":
        _fail("Brussels fallback identity drifted")
        return

    label.set_identity_plaque_enabled(false)
    if panel.visible:
        _fail("baseline toggle did not hide only the authored panel")
        return
    label.set_identity_plaque_enabled(true)
    if not panel.visible:
        _fail("runtime toggle did not restore panel")
        return

    print("BRUSSELS_LOCATION_IDENTITY_BANNER_OK: exposure=production_hud reuse=midi,bourse,grand_place,anneessens,fallback")
    quit(0)
