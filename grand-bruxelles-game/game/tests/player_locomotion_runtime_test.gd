extends SceneTree

const BODY_SCRIPT := preload("res://game/prototypes/player/player_locomotion_body.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_LOCOMOTION_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)

    var floor := StaticBody3D.new()
    var floor_shape := CollisionShape3D.new()
    var floor_box := BoxShape3D.new()
    floor_box.size = Vector3(40.0, 1.0, 40.0)
    floor_shape.shape = floor_box
    floor.add_child(floor_shape)
    floor.position = Vector3(0.0, -0.5, 0.0)
    world.add_child(floor)

    var body := CharacterBody3D.new()
    body.set_script(BODY_SCRIPT)
    var body_shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.35
    capsule.height = 1.8
    body_shape.shape = capsule
    body.add_child(body_shape)
    body.position = Vector3(0.0, 1.2, 0.0)
    world.add_child(body)

    for _i: int in range(20):
        await physics_frame
    if not body.is_on_floor():
        _fail("prototype body did not settle on test floor")
        return

    var start := body.position
    body.call("set_control_state", Vector2(0.0, -1.0), 0.0, true, false)
    for _i: int in range(60):
        await physics_frame
    var travelled := body.position.distance_to(start)
    if travelled < 3.0:
        _fail("runtime sprint travelled too little: %.3f m" % travelled)
        return

    body.call("set_control_state", Vector2.ZERO, 0.0, false, true)
    await physics_frame
    if body.velocity.y <= 0.5:
        _fail("runtime jump did not produce upward velocity: %.3f" % body.velocity.y)
        return

    for _i: int in range(90):
        await physics_frame
    if body.position.y < 0.7:
        _fail("runtime body fell through floor")
        return

    print("PLAYER_LOCOMOTION_RUNTIME_OK: sprint_distance=%.2f jump_velocity=%.2f final_y=%.2f" % [travelled, body.velocity.y, body.position.y])
    quit(0)
