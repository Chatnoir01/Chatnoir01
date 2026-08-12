extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("VISUAL_REALISM_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene failed to load")
        return

    var main: Node = packed.instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await process_frame

    var world_environment: WorldEnvironment = main.get_node_or_null("WorldEnvironment") as WorldEnvironment
    if world_environment == null or world_environment.environment == null:
        _fail("world environment missing")
        return
    if world_environment.environment.background_mode != Environment.BG_SKY:
        _fail("realism sky is not active")
        return
    if not world_environment.environment.fog_enabled:
        _fail("atmospheric fog is not active")
        return

    var urban_life: Node = main.get_node_or_null("MidiUrbanLife")
    if urban_life == null:
        _fail("Midi urban life layer missing")
        return
    if int(urban_life.call("get_pedestrian_count")) < 16:
        _fail("not enough ambient pedestrians")
        return
    if int(urban_life.call("get_parked_vehicle_count")) < 10:
        _fail("not enough parked civilian vehicles")
        return
    if int(urban_life.call("get_moving_vehicle_count")) < 4:
        _fail("not enough ambient moving vehicles")
        return
    if int(urban_life.call("get_prop_count")) < 20:
        _fail("street furniture layer is too sparse")
        return

    var player: Node = main.get_node_or_null("Player")
    if player == null:
        _fail("player missing")
        return
    var player_visual: Node = player.get_node_or_null("VisualUpgrade")
    if player_visual == null or player_visual.get_node_or_null("Torso") == null:
        _fail("articulated player visual missing")
        return
    var legacy_player_mesh: MeshInstance3D = player.get_node_or_null("MeshInstance3D") as MeshInstance3D
    if legacy_player_mesh == null or legacy_player_mesh.visible:
        _fail("legacy player capsule is still visible")
        return

    var civilian_car: Node = main.get_node_or_null("PrototypeCar")
    if civilian_car == null:
        _fail("playable civilian car missing")
        return
    var car_visual: Node = civilian_car.get_node_or_null("VisualUpgrade")
    if car_visual == null or car_visual.get_node_or_null("LowerBody") == null:
        _fail("civilian car visual upgrade missing")
        return
    var legacy_car_body: VisualInstance3D = civilian_car.get_node_or_null("Body") as VisualInstance3D
    if legacy_car_body == null or legacy_car_body.visible:
        _fail("legacy block car body is still visible")
        return

    var prototype_label: CanvasItem = main.get_node_or_null("PrototypeLabel") as CanvasItem
    var police_hint: CanvasItem = main.get_node_or_null("PoliceHintLabel") as CanvasItem
    if prototype_label == null or prototype_label.visible:
        _fail("prototype debug label is still visible")
        return
    if police_hint == null or police_hint.visible:
        _fail("police debug hint is still visible")
        return

    var officer_scene: PackedScene = load("res://game/police/police_officer.tscn") as PackedScene
    var officer: Node = officer_scene.instantiate() if officer_scene != null else null
    if officer == null:
        _fail("police officer scene failed to instantiate")
        return
    main.add_child(officer)
    await process_frame
    var officer_visual: Node = officer.get_node_or_null("VisualUpgrade")
    if officer_visual == null or officer_visual.get_node_or_null("Torso") == null:
        _fail("articulated police visual missing")
        return
    var legacy_officer_body: VisualInstance3D = officer.get_node_or_null("Body") as VisualInstance3D
    if legacy_officer_body == null or legacy_officer_body.visible:
        _fail("legacy police capsule is still visible")
        return

    print("VISUAL_REALISM_SMOKE_OK: sky, atmosphere, humanoids, traffic and street density passed")
    main.queue_free()
    await process_frame
    quit(0)
