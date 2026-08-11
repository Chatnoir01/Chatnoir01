extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("VEHICLE_DAMAGE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var script: Script = load("res://game/scripts/vehicle_damage_model.gd")
    if script == null:
        _fail("damage model script did not load")
        return

    var model: RefCounted = script.new()
    if absf(float(model.call("get_health")) - 100.0) > 0.01:
        _fail("new vehicle must start at 100 health")
        return

    var low: Dictionary = model.call("register_impact", 8.0, 1.0)
    if float(low.get("last_impact_damage", -1.0)) != 0.0:
        _fail("sub-threshold parking impact caused damage")
        return

    var moderate: Dictionary = model.call("register_impact", 45.0, 0.85)
    if float(moderate.get("health", 100.0)) >= 100.0:
        _fail("45 km/h impact did not damage vehicle")
        return
    if float(moderate.get("performance_factor", 1.0)) >= 1.0:
        _fail("mechanical damage did not reduce performance")
        return
    if bool(moderate.get("disabled", true)):
        _fail("single moderate impact disabled vehicle too aggressively")
        return

    var previous_health := float(moderate.get("health", 100.0))
    for _index: int in range(8):
        model.call("register_impact", 70.0, 1.0)
        if bool(model.call("is_disabled")):
            break
    if not bool(model.call("is_disabled")):
        _fail("repeated severe impacts never immobilized vehicle")
        return
    if float(model.call("get_health")) >= previous_health:
        _fail("severe impacts did not accumulate damage")
        return
    if float(model.call("get_performance_factor")) != 0.0:
        _fail("disabled vehicle still exposes drive performance")
        return

    var repaired: Dictionary = model.call("repair", 100.0)
    if bool(repaired.get("disabled", true)):
        _fail("full repair did not restore vehicle")
        return
    if absf(float(repaired.get("health", 0.0)) - 100.0) > 0.01:
        _fail("full repair did not restore 100 health")
        return
    if absf(float(repaired.get("performance_factor", 0.0)) - 1.0) > 0.01:
        _fail("full repair did not restore performance")
        return

    print("VEHICLE_DAMAGE_OK: threshold, cumulative damage, degradation, immobilization and repair passed")
    quit(0)
