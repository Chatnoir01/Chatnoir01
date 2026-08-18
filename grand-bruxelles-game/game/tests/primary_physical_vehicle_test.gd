extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const DYNAMICS_SCRIPT := preload("res://game/scripts/vehicle_dynamics_60hz.gd")
const DT := 1.0 / 60.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PRIMARY_PHYSICAL_VEHICLE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var dynamics := DYNAMICS_SCRIPT.new()
    var speed := 0.0
    for _step: int in range(300):
        speed = dynamics.longitudinal_step(speed, 1.0, 0.0, DT)
    if speed < 16.0 or speed > 20.0:
        _fail("5s full-throttle target drifted: %.3f m/s" % speed)
        return
    var launch_speed := speed
    var braking_steps := 0
    while speed > 0.05 and braking_steps < 180:
        speed = dynamics.longitudinal_step(speed, 0.0, 1.0, DT)
        braking_steps += 1
    if speed > 0.05 or braking_steps > 135:
        _fail("physical brake response too weak: speed=%.3f steps=%d" % [speed, braking_steps])
        return
    var low_speed_steer := absf(dynamics.steer_angle_deg(1.0, 0.0))
    var high_speed_steer := absf(dynamics.steer_angle_deg(1.0, 28.0))
    if low_speed_steer < 30.0 or high_speed_steer >= low_speed_steer or high_speed_steer < 10.0:
        _fail("speed-sensitive steering contract drifted: low=%.2f high=%.2f" % [low_speed_steer, high_speed_steer])
        return
    if dynamics.suspension_force(0.12, 0.0) <= 0.0:
        _fail("suspension force is not positive under compression")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(8):
        await process_frame
    await physics_frame

    var mission := main.get_node_or_null("MissionDriveToCenter")
    var player := main.get_node_or_null("Player") as CharacterBody3D
    var primary := main.get_node_or_null("PhysicalCarB")
    var comparison := main.get_node_or_null("PrototypeCar")
    if mission == null or player == null or primary == null or comparison == null:
        _fail("production mission/player/A+B vehicle nodes missing")
        return
    if not primary is RigidBody3D:
        _fail("mission primary is not the physical RigidBody3D B car")
        return
    if not comparison is CharacterBody3D:
        _fail("arcade A comparison car no longer remains available")
        return
    if str(mission.call("primary_vehicle_node_name")) != "PhysicalCarB":
        _fail("mission primary vehicle identity drifted")
        return
    if mission.get("car") != primary:
        _fail("mission is not bound to PhysicalCarB")
        return
    if not primary.has_method("supported_wheel_count") or not primary.has_method("set_control_state"):
        _fail("physical B controller contract missing")
        return
    var supported := int(primary.call("supported_wheel_count"))
    if supported < 2:
        _fail("physical B car is not resting on enough suspension contacts: %d" % supported)
        return
    var label := main.get_node_or_null("MissionLabel") as Label
    if label == null or label.text.find("B · PHYSIQUE 60 HZ") < 0:
        _fail("mission UI does not direct player to the physical B car")
        return

    primary.call("enter_driver", player)
    await physics_frame
    await process_frame
    if int(mission.call("get_stage")) != 1:
        _fail("entering physical B car did not start Mission 01")
        return
    primary.call("exit_driver")
    var rigid := primary as RigidBody3D
    rigid.linear_velocity = Vector3(7.0, 0.0, -3.0)
    rigid.angular_velocity = Vector3(0.0, 1.5, 0.0)
    mission.call("restart_mission")
    await physics_frame
    var horizontal_speed := Vector2(rigid.linear_velocity.x, rigid.linear_velocity.z).length()
    if horizontal_speed > 0.05 or rigid.angular_velocity.length() > 0.05:
        _fail("mission restart retained horizontal/angular vehicle motion: horizontal=%.3f angular=%.3f" % [horizontal_speed, rigid.angular_velocity.length()])
        return

    print("PRIMARY_PHYSICAL_VEHICLE_OK: mission=B launch5s=%.3f braking=%.2fs steer_low=%.1f steer_high=%.1f suspension_wheels=%d arcade_A_retained=true reset_horizontal=%.3f" % [launch_speed, braking_steps * DT, low_speed_steer, high_speed_steer, supported, horizontal_speed])
    main.queue_free()
    quit(0)
