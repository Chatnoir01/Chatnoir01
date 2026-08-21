extends SceneTree
# Production regression probe: real Y=0 road, tire contact, visual forward and actual forward drive.

const DRIVABLE := preload("res://game/scripts/drivable_traffic_vehicle.gd")
const VISUAL := preload("res://game/scripts/rgsdev_vehicle_visual.gd")
const MODELS := ["sedan", "hatchback", "suv", "van", "pickup", "muscle", "muscle_2", "roadster", "sports", "taxi", "limousine", "ambulance", "bus", "truck", "truck_with_trailer", "firetruck", "monster_truck", "police_sedan", "police_suv", "police_muscle", "police_sports"]

class DummyDriver:
    extends Node

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("VEHICLE_REAL_GROUND_FORWARD_FAIL %s" % message)
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
    floor.collision_layer = 1
    floor.collision_mask = 1
    var floor_collision := CollisionShape3D.new()
    var floor_shape := BoxShape3D.new()
    floor_shape.size = Vector3(120.0, 0.4, 120.0)
    floor_collision.shape = floor_shape
    floor_collision.position = Vector3(0.0, -0.2, 0.0)
    floor.add_child(floor_collision)
    world.add_child(floor)
    for model_id: String in MODELS:
        var holder := CharacterBody3D.new()
        holder.position = Vector3(50.0, 0.6, 50.0)
        var collision := CollisionShape3D.new()
        collision.name = "CollisionShape3D"
        var shape := BoxShape3D.new()
        shape.size = Vector3(2.0, 1.2, 4.6)
        collision.shape = shape
        holder.add_child(collision)
        var visual := VISUAL.new()
        visual.model_id = model_id
        visual.animate_wheels = false
        holder.add_child(visual)
        world.add_child(holder)
        await process_frame
        var contract: Dictionary = visual.get_visual_contract()
        var dot := float(contract.get("visual_forward_dot_body_forward", -1.0))
        if dot < 0.985:
            _fail("visual_forward model=%s dot=%.4f" % [model_id, dot])
            return
        holder.queue_free()
        await process_frame
    var car := DRIVABLE.new() as DrivableTrafficVehicle
    car.position = Vector3(0.0, 1.35, 8.0)
    car.collision_layer = 1
    car.collision_mask = 1
    var car_collision := CollisionShape3D.new()
    car_collision.name = "CollisionShape3D"
    var car_shape := BoxShape3D.new()
    car_shape.size = Vector3(1.82, 1.16, 4.15)
    car_collision.shape = car_shape
    car.add_child(car_collision)
    var car_visual := VISUAL.new()
    car_visual.model_id = "sedan"
    car.add_child(car_visual)
    world.add_child(car)
    car.configure_archetype("car")
    car.configure_as_parked()
    for _frame: int in range(8):
        await physics_frame
    var contract_after_snap: Dictionary = car_visual.get_visual_contract()
    var local_contact := float(contract_after_snap.get("ground_contact_y", INF))
    var world_contact := car.global_position.y + local_contact
    if not is_finite(world_contact) or absf(world_contact - 0.01) > 0.03:
        _fail("world_tire_contact=%.4f body_y=%.4f local=%.4f" % [world_contact, car.global_position.y, local_contact])
        return
    var driver := DummyDriver.new()
    world.add_child(driver)
    if not car.assign_external_driver(driver):
        _fail("external_driver_rejected")
        return
    var start := car.global_position
    var expected_forward := -car.global_transform.basis.z.normalized()
    car.set_external_drive_input(1.0, 0.0, 0.0)
    for _frame: int in range(120):
        await physics_frame
    var displacement := car.global_position - start
    displacement.y = 0.0
    if displacement.length() < 4.0:
        _fail("distance=%.3f" % displacement.length())
        return
    var drive_dot := displacement.normalized().dot(expected_forward)
    if drive_dot < 0.96:
        _fail("forward_drive_dot=%.4f displacement=%s expected=%s" % [drive_dot, str(displacement), str(expected_forward)])
        return
    var visual_dot := float(car_visual.get_visual_contract().get("visual_forward_dot_body_forward", -1.0))
    if visual_dot < 0.985:
        _fail("sedan_visual_dot=%.4f" % visual_dot)
        return
    print("VEHICLE_REAL_GROUND_FORWARD_OK models=%d tire_y=%.4f drive_m=%.3f drive_dot=%.4f visual_dot=%.4f engine=%s" % [MODELS.size(), world_contact, displacement.length(), drive_dot, visual_dot, version])
    quit(0)
