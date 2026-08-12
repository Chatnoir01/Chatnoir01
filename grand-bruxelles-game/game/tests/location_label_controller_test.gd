extends SceneTree

const LOCATION_SCRIPT := preload("res://game/scripts/location_label_controller.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("LOCATION_LABEL_FAIL: %s" % message)
    quit(1)

func _expect(controller: LocationLabelController, position: Vector3, expected: String) -> bool:
    var actual := controller.label_for_world_position(position)
    if actual != expected:
        _fail("%s -> expected '%s', got '%s'" % [position, expected, actual])
        return false
    return true

func _run() -> void:
    var controller := LOCATION_SCRIPT.new() as LocationLabelController
    controller.landmark_radius_m = 185.0
    root.add_child(controller)
    await process_frame

    if not _expect(controller, Vector3(-668.5, 0.0, 627.84), "BRUXELLES-MIDI · BRUSSEL-ZUID"):
        return
    if not _expect(controller, Vector3(-272.04, 0.0, -217.07), "ANNEESSENS"):
        return
    if not _expect(controller, Vector3(81.54, 0.0, -664.58), "BOURSE · BEURS"):
        return
    if not _expect(controller, Vector3(319.01, 0.0, -535.20), "GRAND-PLACE · GROTE MARKT"):
        return
    if not _expect(controller, Vector3(-50.0, 0.0, 180.0), "BRUXELLES · BRUSSEL"):
        return

    print("LOCATION_LABEL_OK: Midi, Anneessens, Bourse, Grand-Place and generic Brussels fallback")
    controller.queue_free()
    quit(0)
