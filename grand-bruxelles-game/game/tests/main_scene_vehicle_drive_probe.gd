extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")

class DummyDriver:
    extends Node

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MAIN_SCENE_VEHICLE_DRIVE_FAIL %s" % message)
    quit(1)

func _run() -> void:
    var info := Engine.get_version_info()
    var version := "%d.%d.%d" % [int(info.major), int(info.minor), int(info.patch)]
    if version != "4.7.1":
        _fail("engine=%s" % version)
        return

    var main := MAIN_SCENE.instantiate() as Node3D
    if main == null:
        _fail("main_scene_instantiate")
        return

    # Keep the exact serialized road/vehicle nodes from main.tscn while removing
    # unrelated city systems before _ready(), so the probe stays deterministic.
    var keep := {
        "Ground": true,
        "Player": true,
        "PrototypeCar": true,
        "PhysicalCarB": true,
        "TrafficManager": true,
        "MobileControls": true,
    }
    for child: Node in main.get_children():
        if not keep.has(child.name):
            main.remove_child(child)
            child.free()

    var manager := main.get_node_or_null("TrafficManager")
    if manager != null:
        manager.set("auto_load_data", false)
        manager.set("auto_spawn_runtime", false)

    root.add_child(main)
    await process_frame
    await process_frame
    await physics_frame
    await physics_frame

    if main.get_node_or_null("PhysicalCarB") != null:
        _fail("legacy_physical_car_still_active")
        return

    var car := main.get_node_or_null("PrototypeCar") as CharacterBody3D
    if car == null:
        _fail("prototype_missing")
        return
    if not car.has_method("assign_external_driver") or not car.has_method("set_external_drive_input"):
        _fail("prototype_not_using_production_drive_contract")
        return

    # main.tscn Ground: center -0.23, height 0.4 => road top -0.03 m.
    var road_top_y := -0.03
    for _frame: int in range(6):
        await physics_frame

    var collision := car.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collision == null or not collision.shape is BoxShape3D:
        _fail("starter_collision_missing")
        return
    var box := collision.shape as BoxShape3D
    var collision_bottom_world := car.global_position.y + collision.position.y - box.size.y * 0.5
    if absf(collision_bottom_world - (road_top_y + 0.01)) > 0.035:
        _fail("collision_ground body_y=%.4f bottom=%.4f expected=%.4f" % [car.global_position.y, collision_bottom_world, road_top_y + 0.01])
        return

    var visual := car.get_node_or_null("RgsdevVisual")
    if visual == null or not visual.has_method("get_visual_contract"):
        _fail("rgsdev_visual_missing")
        return
    var contract: Dictionary = visual.call("get_visual_contract")
    var tire_local_y := float(contract.get("ground_contact_y", INF))
    var tire_world_y := car.global_position.y + tire_local_y
    if not is_finite(tire_world_y) or absf(tire_world_y - (road_top_y + 0.01)) > 0.04:
        _fail("tire_ground world=%.4f expected=%.4f" % [tire_world_y, road_top_y + 0.01])
        return

    var visual_forward_dot := float(contract.get("visual_forward_dot_body_forward", -1.0))
    if visual_forward_dot < 0.985:
        _fail("visual_forward_dot=%.4f" % visual_forward_dot)
        return

    var driver := DummyDriver.new()
    main.add_child(driver)
    if not bool(car.call("assign_external_driver", driver)):
        _fail("external_driver_rejected")
        return

    var start := car.global_position
    var expected_forward := -car.global_transform.basis.z.normalized()
    car.call("set_external_drive_input", 1.0, 0.0, 0.0)
    for _frame: int in range(120):
        await physics_frame

    var displacement := car.global_position - start
    displacement.y = 0.0
    if displacement.length() < 4.0:
        _fail("distance=%.3f" % displacement.length())
        return
    var drive_dot := displacement.normalized().dot(expected_forward)
    if drive_dot < 0.96:
        _fail("drive_dot=%.4f displacement=%s expected=%s" % [drive_dot, str(displacement), str(expected_forward)])
        return

    print("MAIN_SCENE_VEHICLE_DRIVE_OK ground=%.4f tire=%.4f distance=%.3f drive_dot=%.4f visual_dot=%.4f engine=%s" % [collision_bottom_world, tire_world_y, displacement.length(), drive_dot, visual_forward_dot, version])
    quit(0)
