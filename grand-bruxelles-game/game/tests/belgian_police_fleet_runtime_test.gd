extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/belgian_police_fleet_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BELGIAN_POLICE_FLEET_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "BelgianPoliceFleetRuntimeTestSubject"
    root.add_child(runtime)
    if int(runtime.call("profile_count")) != 5:
        _fail("profile count is not exactly five")
        return
    var ids: Array = runtime.call("profile_ids") as Array
    if ids.size() != 5:
        _fail("profile id list size mismatch")
        return
    var unique: Dictionary = {}
    for value: Variant in ids:
        unique[str(value)] = true
    if unique.size() != 5:
        _fail("profile ids are not unique")
        return
    var contract: Dictionary = runtime.call("get_contract") as Dictionary
    if not bool(contract.get("renderer_only", false)):
        _fail("renderer_only contract missing")
        return
    for forbidden_key: String in ["changes_physics", "changes_collision", "changes_traffic_motion", "changes_geography"]:
        if bool(contract.get(forbidden_key, true)):
            _fail("forbidden mutation enabled: %s" % forbidden_key)
            return
    if bool(contract.get("third_party_gta_geometry_committed", true)):
        _fail("GTA geometry must remain excluded")
        return
    if not bool(contract.get("reference_only_sources_fail_closed", false)):
        _fail("reference-only sources are not fail-closed")
        return
    var sandbox := Node3D.new()
    sandbox.name = "BelgianPoliceFleetSandbox"
    root.add_child(sandbox)
    for index: int in range(5):
        var vehicle := StaticBody3D.new()
        vehicle.name = "FleetVehicle_%02d" % index
        vehicle.position = Vector3(float(index) * 7.0, 0.0, -3.0)
        var collision := CollisionShape3D.new()
        collision.name = "ExistingCollision"
        var shape := BoxShape3D.new()
        shape.size = Vector3(1.9, 0.9, 4.2)
        collision.shape = shape
        vehicle.add_child(collision)
        var fallback := Node3D.new()
        fallback.name = "ProductionVisual"
        vehicle.add_child(fallback)
        sandbox.add_child(vehicle)
        var original_transform := vehicle.transform
        var original_shape := collision.shape
        var original_shape_size := shape.size
        if not bool(runtime.call("apply_profile_to_vehicle", vehicle, index)):
            _fail("profile %d failed to apply" % index)
            return
        if vehicle.transform != original_transform:
            _fail("profile %d changed vehicle transform" % index)
            return
        if collision.shape != original_shape or shape.size != original_shape_size:
            _fail("profile %d changed collision" % index)
            return
        if fallback.visible:
            _fail("profile %d did not hide recoverable fallback" % index)
            return
        var holder := vehicle.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
        if holder == null:
            _fail("profile %d did not mount fleet visual" % index)
            return
        if str(holder.get_meta("police_profile_id", "")) != str(ids[index]):
            _fail("profile %d metadata mismatch" % index)
            return
        if not bool(holder.get_meta("renderer_only", false)):
            _fail("profile %d renderer-only metadata missing" % index)
            return
        if bool(holder.get_meta("production_authorized_exact_third_party_geometry", true)):
            _fail("profile %d incorrectly authorizes exact third-party geometry" % index)
            return
        if not vehicle.is_in_group("belgian_police_vehicle"):
            _fail("profile %d missing Belgian police group" % index)
            return
        runtime.call("set_profile_visible", vehicle, false)
        if holder.visible or not fallback.visible:
            _fail("profile %d A/B OFF did not restore fallback" % index)
            return
        runtime.call("set_profile_visible", vehicle, true)
        if not holder.visible or fallback.visible:
            _fail("profile %d A/B ON did not restore police visual" % index)
            return
        if not bool(runtime.call("apply_profile_to_vehicle", vehicle, index)):
            _fail("profile %d idempotent reapply failed" % index)
            return
        var holder_count := 0
        for child: Node in vehicle.get_children():
            if child.name == "BelgianPoliceFleetVisual":
                holder_count += 1
        if holder_count != 1:
            _fail("profile %d duplicated fleet visual" % index)
            return
    await process_frame
    print("BELGIAN_POLICE_FLEET_OK: profiles=5 unique=5 physics_unchanged=true collision_unchanged=true fallback_recoverable=true gta_geometry_excluded=true")
    quit(0)
