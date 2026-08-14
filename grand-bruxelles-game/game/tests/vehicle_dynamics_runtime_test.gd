extends SceneTree

const BODY_SCRIPT := preload("res://game/prototypes/vehicle/vehicle_dynamics_body.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("VEHICLE_DYNAMICS_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)

    var floor := StaticBody3D.new()
    var floor_shape := CollisionShape3D.new()
    var floor_box := BoxShape3D.new()
    floor_box.size = Vector3(60.0, 1.0, 60.0)
    floor_shape.shape = floor_box
    floor.add_child(floor_shape)
    floor.position = Vector3(0.0, -0.5, 0.0)
    world.add_child(floor)

    var car := RigidBody3D.new()
    car.set_script(BODY_SCRIPT)
    var car_shape := CollisionShape3D.new()
    var car_box := BoxShape3D.new()
    car_box.size = Vector3(1.82, 0.72, 4.15)
    car_shape.shape = car_box
    car.add_child(car_shape)
    car.position = Vector3(0.0, 0.78, 0.0)
    world.add_child(car)

    for _i: int in range(90):
        await physics_frame
    if car.position.y < 0.45:
        _fail("suspended chassis settled too low: %.3f" % car.position.y)
        return
    var supported := int(car.call("supported_wheel_count"))
    if supported < 3:
        _fail("raycast suspension did not support enough wheels: %d" % supported)
        return

    var start := car.position
    car.call("set_control_state", 1.0, 0.0, 0.0)
    for _i: int in range(180):
        await physics_frame
    var driven_distance := Vector2(car.position.x - start.x, car.position.z - start.z).length()
    var speed_before_brake := absf(float(car.call("forward_speed_ms")))
    if driven_distance < 8.0 or speed_before_brake < 5.0:
        _fail("runtime vehicle acceleration too weak: distance=%.3f speed=%.3f" % [driven_distance, speed_before_brake])
        return

    car.call("set_control_state", 0.0, 1.0, 0.0)
    for _i: int in range(240):
        await physics_frame
    var speed_after_brake := absf(float(car.call("forward_speed_ms")))
    if speed_after_brake > maxf(0.8, speed_before_brake * 0.20):
        _fail("runtime braking insufficient: before=%.3f after=%.3f" % [speed_before_brake, speed_after_brake])
        return
    if car.position.y < 0.35:
        _fail("runtime suspended chassis collapsed through floor")
        return

    print("VEHICLE_DYNAMICS_RUNTIME_OK: wheels=%d distance=%.2f speed_before=%.2f speed_after=%.2f final_y=%.2f" % [supported, driven_distance, speed_before_brake, speed_after_brake, car.position.y])
    quit(0)
