extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/stib_surface_stop_visual.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("STIB_SURFACE_STOP_VISUAL_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var visual := VISUAL_SCRIPT.new()
    root.add_child(visual)
    await process_frame
    if not bool(visual.get("visual_built")):
        _fail("surface-stop visual did not build")
        return
    if int(visual.get("pole_count")) != 1:
        _fail("expected one stop pole")
        return
    if int(visual.get("timetable_panel_count")) != 1:
        _fail("expected one timetable holder/panel")
        return
    if int(visual.get("shelter_count")) != 1:
        _fail("expected one shelter")
        return
    if int(visual.get("bench_count")) != 1:
        _fail("expected one bench")
        return
    if int(visual.get("bin_count")) != 1:
        _fail("expected one bin")
        return
    if float(visual.get("rear_clearance_m")) < 1.50:
        _fail("shelter rear clearance contract below STIB minimum")
        return
    if float(visual.get("front_clearance_m")) < 1.50:
        _fail("shelter front clearance contract below STIB minimum")
        return
    print("STIB_SURFACE_STOP_VISUAL_OK: pole=1 timetable=1 shelter=1 bench=1 bin=1 clearances>=1.50m")
    visual.queue_free()
    quit(0)
