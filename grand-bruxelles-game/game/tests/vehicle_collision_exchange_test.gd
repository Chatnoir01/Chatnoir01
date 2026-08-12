extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("VEHICLE_COLLISION_EXCHANGE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/main.tscn")
    if packed == null:
        _fail("main scene did not load")
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)
    await process_frame

    var player_car := scene.get_node_or_null("PrototypeCar")
    var manager := scene.get_node_or_null("TrafficManager")
    var traffic_root := scene.get_node_or_null("TrafficManager/TrafficVehicles")
    if player_car == null or manager == null or traffic_root == null:
        _fail("player vehicle or traffic runtime missing")
        return

    if not player_car.has_method("_transmit_impact_to_collider"):
        _fail("player vehicle impact transmission API missing")
        return
    if not manager.has_method("_create_vehicle_node"):
        _fail("traffic vehicle factory missing")
        return

    var ai: CharacterBody3D = manager.call("_create_vehicle_node") as CharacterBody3D
    if ai == null:
        _fail("AI vehicle factory returned null")
        return
    traffic_root.add_child(ai)
    await process_frame

    for method_name: String in [
        "_transmit_impact_to_collider",
        "apply_external_impact",
        "get_traffic_vehicle_health",
    ]:
        if not ai.has_method(method_name):
            _fail("AI collision exchange API missing: %s" % method_name)
            return

    var ai_health_before := float(ai.call("get_traffic_vehicle_health"))
    if not bool(player_car.call("_transmit_impact_to_collider", ai, 60.0, 1.0)):
        _fail("player vehicle refused to transmit impact to AI")
        return
    var ai_health_after := float(ai.call("get_traffic_vehicle_health"))
    if ai_health_after >= ai_health_before:
        _fail("player -> AI impact did not reduce AI health")
        return

    var player_health_before := float(player_car.call("get_vehicle_health"))
    if not bool(ai.call("_transmit_impact_to_collider", player_car, 60.0, 1.0)):
        _fail("AI vehicle refused to transmit impact to player vehicle")
        return
    var player_health_after := float(player_car.call("get_vehicle_health"))
    if player_health_after >= player_health_before:
        _fail("AI -> player impact did not reduce player vehicle health")
        return

    scene.queue_free()
    await process_frame
    print(
        "VEHICLE_COLLISION_EXCHANGE_OK: player->AI %.1f->%.1f, AI->player %.1f->%.1f" %
        [ai_health_before, ai_health_after, player_health_before, player_health_after]
    )
    quit(0)
