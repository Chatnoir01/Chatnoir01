extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_RUNTIME_CONTRACT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var contract_script: Script = load("res://game/scripts/traffic_runtime_contract.gd")
    if contract_script == null:
        _fail("contract script did not load")
        return

    var contract := contract_script.new()
    if contract.MANAGER_METHODS.size() < 17:
        _fail("manager contract lost required v8 behavior")
        return
    if contract.VEHICLE_METHODS.size() < 9:
        _fail("vehicle contract lost required behavior")
        return
    if not contract.MANAGER_METHODS.has("get_wreck_count") or not contract.MANAGER_METHODS.has("cleanup_wrecks_at"):
        _fail("wreck lifecycle from active v8 baseline is not protected")
        return
    if not contract.OPTIONAL_TOW_METHODS.has("process_tow_services_at"):
        _fail("v9 tow behavior is not represented as an explicit optional extension")
        return
    if contract.ACTIVE_LEGACY_BASELINE != "traffic_manager_core_v8":
        _fail("active legacy baseline must remain v8 until parity is proven")
        return
    if contract.CANONICAL_MANAGER_TARGET.find("_v") >= 0 or contract.CANONICAL_VEHICLE_TARGET.find("_v") >= 0:
        _fail("canonical targets must not introduce another version-suffixed core")
        return

    var incomplete := Node.new()
    var missing: PackedStringArray = contract.validate_manager(incomplete)
    if missing.size() != contract.MANAGER_METHODS.size():
        _fail("missing-method detector is not deterministic")
        return
    incomplete.free()

    print("TRAFFIC_RUNTIME_CONTRACT_OK: %d manager methods, %d vehicle methods, %d optional tow methods" % [
        contract.MANAGER_METHODS.size(),
        contract.VEHICLE_METHODS.size(),
        contract.OPTIONAL_TOW_METHODS.size(),
    ])
    quit(0)
