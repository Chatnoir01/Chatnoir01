extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("VEHICLE_RECOVERY_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var script: Script = load("res://game/scripts/vehicle_recovery_model.gd")
    if script == null:
        _fail("recovery model script did not load")
        return

    var model: RefCounted = script.new()
    var light_quote := float(model.call("estimate_quote", 10.0, 20.0))
    var heavy_quote := float(model.call("estimate_quote", 80.0, 100.0))
    if heavy_quote <= light_quote:
        _fail("recovery quote does not scale with damage")
        return

    var requested: Dictionary = model.call("request_recovery", 80.0, 100.0, 10.0, 4.0)
    if str(requested.get("state", "")) != "requested":
        _fail("recovery did not enter requested state")
        return
    if absf(float(requested.get("remaining_seconds", 0.0)) - 4.0) > 0.01:
        _fail("recovery delay mismatch")
        return
    if bool(model.call("is_ready", 13.9)):
        _fail("recovery completed before delay")
        return
    if not bool(model.call("is_ready", 14.0)):
        _fail("recovery not ready after delay")
        return

    var completed: Dictionary = model.call("complete_recovery", 14.0)
    if str(completed.get("state", "")) != "recovered":
        _fail("recovery did not complete")
        return
    if float(completed.get("roadside_repair_amount", 0.0)) <= 0.0:
        _fail("roadside recovery did not expose repair amount")
        return

    model.call("reset")
    if str(model.get("state")) != "idle":
        _fail("recovery reset failed")
        return

    print("VEHICLE_RECOVERY_OK: scaled quote, delay, completion and roadside repair passed")
    quit(0)
