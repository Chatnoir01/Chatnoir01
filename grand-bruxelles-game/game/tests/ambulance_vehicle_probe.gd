extends SceneTree

const AMBULANCE_SCRIPT := preload("res://game/scripts/ambulance_vehicle.gd")
const VISUAL_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")
const TRAFFIC_SCRIPT := preload("res://game/scripts/traffic_vehicle_core.gd")
const MANAGER_SCRIPT := preload("res://game/scripts/traffic_manager_npc_crossing_extension.gd")

class DummyDriver:
    extends Node

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AMBULANCE_PROBE_FAIL %s" % message)
    quit(1)

func _run() -> void:
    var info := Engine.get_version_info()
    var version := "%d.%d.%d" % [int(info.major), int(info.minor), int(info.patch)]
    if version != "4.7.1":
        _fail("engine=%s" % version)
        return

    var world := Node3D.new()
    root.add_child(world)

    var floor := StaticBody3D.new()
    var floor_collision := CollisionShape3D.new()
    var floor_shape := BoxShape3D.new()
    floor_shape.size = Vector3(80.0, 0.4, 80.0)
    floor_collision.shape = floor_shape
    floor_collision.position = Vector3(0.0, -0.2, 0.0)
    floor.add_child(floor_collision)
    world.add_child(floor)

    var manager := MANAGER_SCRIPT.new()
    manager.auto_load_data = false
    manager.auto_spawn_runtime = false
    manager.dedicated_ambulance_count = 2
    world.add_child(manager)
    for _frame: int in range(4):
        await process_frame
    if manager.get_ambulance_count() != 2:
        _fail("dedicated_count=%d" % manager.get_ambulance_count())
        return
    var special_nodes := get_nodes_in_group("emergency_vehicle")
    if special_nodes.size() != 2:
        _fail("special_vehicle_count=%d expected=2" % special_nodes.size())
        return
    for node: Node in special_nodes:
        if not node is AMBULANCE_SCRIPT:
            _fail("non_ambulance_special_spawned=%s" % node.name)
            return
        if str(node.get_meta("special_vehicle_kind", "")) != "ambulance":
            _fail("wrong_special_kind=%s" % node.name)
            return

    var ambulance := AMBULANCE_SCRIPT.new() as AmbulanceVehicle
    ambulance.position = Vector3(0.0, 1.08, 0.0)
    ambulance.collision_layer = 1
    ambulance.collision_mask = 1
    var ambulance_collision := CollisionShape3D.new()
    var ambulance_shape := BoxShape3D.new()
    ambulance_shape.size = Vector3(2.08, 2.12, 5.28)
    ambulance_collision.shape = ambulance_shape
    ambulance.add_child(ambulance_collision)
    var visual := VISUAL_SCRIPT.new()
    visual.configure_model("ambulance")
    ambulance.add_child(visual)
    world.add_child(ambulance)
    ambulance.configure_archetype("car")

    var siren := ambulance.get_node_or_null("Siren3D") as AudioStreamPlayer3D
    if siren == null or not siren.stream is AudioStreamWAV:
        _fail("siren_stream_missing")
        return
    var siren_stream := siren.stream as AudioStreamWAV
    if siren_stream.data.size() < 1000 or siren_stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
        _fail("siren_stream_invalid bytes=%d loop=%d" % [siren_stream.data.size(), siren_stream.loop_mode])
        return
    if ambulance.is_siren_playing():
        _fail("siren_playing_while_emergency_off")
        return

    var traffic := TRAFFIC_SCRIPT.new() as TrafficVehicleCore
    traffic.position = Vector3(0.0, 1.0, -7.0)
    traffic.speed_factor = 0.83
    traffic.add_to_group("traffic_vehicle")
    var traffic_collision := CollisionShape3D.new()
    var traffic_shape := BoxShape3D.new()
    traffic_shape.size = Vector3(1.82, 1.16, 4.15)
    traffic_collision.shape = traffic_shape
    traffic.add_child(traffic_collision)
    world.add_child(traffic)

    for _frame: int in range(4):
        await physics_frame
    ambulance.set_emergency_mode(true)
    for _frame: int in range(4):
        await process_frame
    if not ambulance.is_emergency_mode():
        _fail("emergency_mode_not_enabled")
        return
    if not ambulance.is_siren_playing():
        _fail("siren_not_playing_in_emergency")
        return
    if float(traffic.speed_factor) > ambulance.yielded_speed_factor + 0.001:
        _fail("traffic_did_not_yield speed_factor=%.3f" % traffic.speed_factor)
        return

    ambulance.set_emergency_mode(false)
    await process_frame
    if ambulance.is_siren_playing():
        _fail("siren_still_playing_after_emergency_off")
        return
    if absf(float(traffic.speed_factor) - 0.83) > 0.001:
        _fail("traffic_speed_not_restored=%.3f" % traffic.speed_factor)
        return

    traffic.global_position = Vector3(22.0, 1.0, 22.0)
    await physics_frame

    var driver := DummyDriver.new()
    world.add_child(driver)
    if not ambulance.assign_external_driver(driver):
        _fail("external_driver_rejected")
        return
    ambulance.set_external_drive_input(1.0, 0.0, 0.0)
    var start := ambulance.global_position
    for _frame: int in range(150):
        await physics_frame
    var displacement := ambulance.global_position.distance_to(start)
    if displacement < 4.0:
        _fail("ambulance_did_not_drive displacement=%.3f" % displacement)
        return
    ambulance.release_external_driver(driver)

    var contract := ambulance.get_ambulance_contract()
    if not bool(contract.get("drivable", false)) or not bool(contract.get("external_driver_supported", false)):
        _fail("contract_missing_driving_support")
        return
    if not bool(contract.get("siren", false)) or not bool(contract.get("siren_spatial_3d", false)):
        _fail("contract_missing_siren")
        return
    if bool(contract.get("other_special_vehicles_auto_spawned", true)):
        _fail("other_special_vehicles_enabled")
        return

    print("AMBULANCE_PROBE_OK ambulances=2 emergency=true siren=true yield_restore=true external_drive_m=%.3f other_special=false engine=%s" % [displacement, version])
    quit(0)
