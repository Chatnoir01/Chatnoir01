extends SceneTree

const MANAGER_PATH := "res://game/scripts/traffic_manager_core.gd"
const VEHICLE_PATH := "res://game/scripts/traffic_vehicle_core.gd"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_CANONICAL_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not ResourceLoader.exists(MANAGER_PATH):
        _fail("canonical manager is missing: %s" % MANAGER_PATH)
        return
    if not ResourceLoader.exists(VEHICLE_PATH):
        _fail("canonical vehicle core is missing: %s" % VEHICLE_PATH)
        return

    var contract_script: Script = load("res://game/scripts/traffic_runtime_contract.gd")
    if contract_script == null:
        _fail("traffic runtime contract did not load")
        return
    var contract: TrafficRuntimeContract = contract_script.new()

    var manager_script: Script = load(MANAGER_PATH)
    var vehicle_script: Script = load(VEHICLE_PATH)
    if manager_script == null or vehicle_script == null:
        _fail("canonical scripts failed to load")
        return

    var manager: Object = manager_script.new()
    var vehicle: Object = vehicle_script.new()
    var manager_missing: PackedStringArray = contract.validate_manager(manager)
    var vehicle_missing: PackedStringArray = contract.validate_vehicle(vehicle)

    if not manager_missing.is_empty():
        _fail("canonical manager missing methods: %s" % ", ".join(manager_missing))
        return
    if not vehicle_missing.is_empty():
        _fail("canonical vehicle missing methods: %s" % ", ".join(vehicle_missing))
        return

    if manager_script.resource_path.find("_core_v") >= 0 or vehicle_script.resource_path.find("_core_v") >= 0:
        _fail("canonical runtime must not resolve to a version-suffixed core")
        return

    print("TRAFFIC_CANONICAL_RUNTIME_OK: manager=%s vehicle=%s" % [manager_script.resource_path, vehicle_script.resource_path])
    quit(0)
