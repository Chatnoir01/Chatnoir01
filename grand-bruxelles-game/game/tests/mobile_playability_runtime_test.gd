extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MOBILE_PLAYABILITY_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    await process_frame
    await process_frame
    await physics_frame

    var mobile := main.get_node_or_null("MobileControls")
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if mobile == null or player == null:
        _fail("main scene is missing mobile controls or player")
        return
    if not mobile.has_method("get_movement_vector"):
        _fail("mobile controls do not expose analog movement")
        return
    if not player.has_method("cycle_camera_view") or not player.has_method("fast_travel_to"):
        _fail("player is missing camera-view or fast-travel mobile contracts")
        return

    var arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    if arm == null:
        _fail("player spring arm missing")
        return
    var initial_distance := arm.spring_length
    player.call("cycle_camera_view")
    if is_equal_approx(arm.spring_length, initial_distance):
        _fail("camera view cycle did not change follow distance")
        return

    if not bool(player.call("fast_travel_to", "bourse")):
        _fail("Bourse fast travel was rejected")
        return
    if Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(83.44, -663.42)) > 0.1:
        _fail("Bourse fast travel landed at the wrong position")
        return
    player.call("fast_travel_to", "vehicle_ab")

    var vehicles := get_nodes_in_group("vehicle")
    var legacy_count := 0
    var physical_count := 0
    for vehicle: Node in vehicles:
        if vehicle is RigidBody3D:
            physical_count += 1
        elif vehicle is CharacterBody3D:
            legacy_count += 1
    if legacy_count < 1 or physical_count < 1:
        _fail("main world does not expose both A and B drivable vehicle types")
        return

    var collision_runtime := main.get_node_or_null("MobilePlayabilityCollisionRuntime")
    if collision_runtime == null:
        _fail("playability collision runtime missing")
        return

    var npc := NpcAgent.new()
    npc.name = "CollisionProbeNpc"
    main.add_child(npc)
    var ambient := Node3D.new()
    ambient.name = "CollisionProbeAmbient"
    ambient.add_to_group("ambient_pedestrian")
    main.add_child(ambient)
    await process_frame
    await process_frame

    if npc.get_node_or_null("RuntimeCharacterCollision") == null:
        _fail("NpcAgent did not receive a physical capsule")
        return
    if ambient.get_node_or_null("RuntimeCollisionBody/CollisionShape3D") == null:
        _fail("ambient pedestrian did not receive a physical body")
        return

    var physical_car := main.get_node_or_null("PhysicalCarB")
    if physical_car == null or not physical_car.has_method("supported_wheel_count"):
        _fail("physical B car runtime controller missing")
        return

    print("MOBILE_PLAYABILITY_OK: analog=true camera_views=true fast_travel=true vehicles=A+B npc_collision=true ambient_collision=true")
    quit(0)
