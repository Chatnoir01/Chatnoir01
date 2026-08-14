extends SceneTree

const SANDBOX := preload("res://game/prototypes/vehicle/vehicle_ab_sandbox.tscn")


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("VEHICLE_AB_SANDBOX_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var sandbox := SANDBOX.instantiate()
    root.add_child(sandbox)

    for _i: int in range(90):
        await physics_frame

    var player := sandbox.get_node_or_null("Player") as CharacterBody3D
    var legacy := sandbox.get_node_or_null("LegacyCar") as CharacterBody3D
    var physical := sandbox.get_node_or_null("PhysicalCar") as RigidBody3D
    if player == null or legacy == null or physical == null:
        _fail("sandbox did not instantiate player + both vehicle variants")
        return

    var legacy_visual := legacy.get_node_or_null("VisualUpgrade")
    var physical_visual := physical.get_node_or_null("VisualUpgrade")
    if legacy_visual == null or physical_visual == null:
        _fail("A/B cars do not share the in-game civilian visual component")
        return
    if legacy_visual.get_child_count() < 10 or physical_visual.get_child_count() < 10:
        _fail("civilian vehicle visual did not build on both variants")
        return

    var supported := int(physical.call("supported_wheel_count"))
    if supported < 3:
        _fail("physical car is not supported by suspension rays: wheels=%d" % supported)
        return

    var start := physical.global_position
    physical.call("set_control_state", 1.0, 0.0, 0.0)
    for _i: int in range(180):
        await physics_frame
    var distance := Vector2(
        physical.global_position.x - start.x,
        physical.global_position.z - start.z
    ).length()
    var speed_before := absf(float(physical.call("forward_speed_ms")))
    if distance < 8.0 or speed_before < 5.0:
        _fail("physical playable car acceleration too weak: distance=%.2f speed=%.2f" % [distance, speed_before])
        return

    physical.call("set_control_state", 0.0, 1.0, 0.0)
    for _i: int in range(240):
        await physics_frame
    var speed_after := absf(float(physical.call("forward_speed_ms")))
    if speed_after > 0.8:
        _fail("physical playable car did not brake: before=%.2f after=%.2f" % [speed_before, speed_after])
        return

    physical.call("clear_control_override")
    physical.call("enter_driver", player)
    await physics_frame
    if not bool(physical.call("has_driver")):
        _fail("physical car rejected the production player enter API")
        return
    if player.visible or player.collision_layer != 0 or player.collision_mask != 0:
        _fail("production player did not enter vehicle mode")
        return

    physical.call("exit_driver")
    await physics_frame
    if bool(physical.call("has_driver")):
        _fail("physical car kept driver after exit")
        return
    if not player.visible or player.collision_layer == 0:
        _fail("production player did not recover after physical-car exit")
        return

    print("VEHICLE_AB_SANDBOX_OK: shared_visual=true wheels=%d distance=%.2f speed_before=%.2f speed_after=%.2f enter_exit=true" % [supported, distance, speed_before, speed_after])
    quit(0)
