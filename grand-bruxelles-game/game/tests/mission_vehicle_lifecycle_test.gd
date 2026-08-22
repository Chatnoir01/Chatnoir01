extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const MISSION_SCRIPT_PATH := "res://game/scripts/mission_drive_to_center.gd"
const PRODUCTION_VEHICLE_NODE := "PrototypeCar"
const REMOVED_PROTOTYPE_NODE := "PhysicalCarB"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_VEHICLE_LIFECYCLE_FAIL: %s" % message)
    quit(1)


func _find_mission(node: Node) -> Node:
    var script: Variant = node.get_script()
    if script is Script and str((script as Script).resource_path) == MISSION_SCRIPT_PATH:
        return node
    for child: Node in node.get_children():
        var found: Node = _find_mission(child)
        if found != null:
            return found
    return null


func _run() -> void:
    var main: Node = MAIN_SCENE.instantiate()
    root.add_child(main)

    # Let the production traffic extension execute its deferred cleanup and let
    # the mission run physics frames after that cleanup. This reproduces the
    # real use-after-free that previously spammed corridor/runtime witnesses.
    for _frame: int in range(24):
        await process_frame
        await physics_frame

    if main.get_node_or_null(REMOVED_PROTOTYPE_NODE) != null:
        _fail("obsolete PhysicalCarB prototype was not removed by production runtime")
        return

    var production_vehicle := main.get_node_or_null(PRODUCTION_VEHICLE_NODE) as Node3D
    if production_vehicle == null or not is_instance_valid(production_vehicle):
        _fail("production PrototypeCar missing after cleanup")
        return
    for required_method: String in ["has_driver", "exit_driver"]:
        if not production_vehicle.has_method(required_method):
            _fail("production vehicle contract missing method: %s" % required_method)
            return

    var mission: Node = _find_mission(main)
    if mission == null:
        _fail("MissionDriveToCenter runtime missing")
        return
    if not mission.has_method("primary_vehicle_node_name"):
        _fail("mission primary vehicle contract missing")
        return
    if str(mission.call("primary_vehicle_node_name")) != PRODUCTION_VEHICLE_NODE:
        _fail("mission still binds removed vehicle: %s" % str(mission.call("primary_vehicle_node_name")))
        return
    if not mission.has_method("primary_vehicle_is_valid"):
        _fail("mission cannot prove its live primary vehicle reference")
        return
    if not bool(mission.call("primary_vehicle_is_valid")):
        _fail("mission primary vehicle reference is invalid after prototype cleanup")
        return

    # Continue long enough to catch deferred/lifecycle regressions after the
    # obsolete prototype is gone. The workflow also rejects any SCRIPT ERROR.
    for _frame: int in range(36):
        await process_frame
        await physics_frame

    if not bool(mission.call("primary_vehicle_is_valid")):
        _fail("mission primary vehicle became invalid during steady-state physics")
        return

    print("MISSION_VEHICLE_LIFECYCLE_GREEN production_vehicle=%s removed_prototype=true reference_valid=true" % PRODUCTION_VEHICLE_NODE)
    quit(0)
