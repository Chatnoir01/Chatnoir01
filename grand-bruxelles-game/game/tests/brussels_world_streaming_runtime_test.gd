extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const CELL_ID := "bxl-e149000-n169000-s500"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_WORLD_STREAMING_RUNTIME_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _wait_frames(count: int) -> void:
    for _index: int in range(count):
        await process_frame

func _wait_until(predicate: Callable, max_frames: int) -> bool:
    for _index: int in range(max_frames):
        await process_frame
        if bool(predicate.call()):
            return true
    return false

func _cell_ready(streamer: Node) -> bool:
    if not streamer.has_method("is_ixelles_active") or not bool(streamer.call("is_ixelles_active")):
        return false
    var backend: Node = streamer.call("get_backend")
    if backend == null or not backend.has_method("get_instance"):
        return false
    var instance: Node = backend.call("get_instance", CELL_ID)
    return is_instance_valid(instance) and bool(instance.get("runtime_loaded"))

func _collision_present(streamer: Node) -> bool:
    if not _cell_ready(streamer):
        return false
    var backend: Node = streamer.call("get_backend")
    var instance: Node = backend.call("get_instance", CELL_ID)
    return is_instance_valid(instance) and instance.find_child("OfficialIxellesDTMCollision", true, false) != null

func _fast_travel_done(streamer: Node, player: CharacterBody3D, center: Vector3) -> bool:
    return bool(streamer.call("is_ixelles_active")) and _collision_present(streamer) and player.global_position.distance_to(center) < 400.0

func _ixelles_button_present(mobile: Node) -> bool:
    var panel := mobile.find_child("FastTravelPanel", true, false)
    if panel == null:
        return false
    for child: Node in panel.get_children():
        if child is Button and (child as Button).text == "IXELLES / ELSENE":
            return true
    return false

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await _wait_frames(4)

    var streamer := main.get_node_or_null("BrusselsWorldStreamer")
    var player := main.get_node_or_null("Player") as CharacterBody3D
    var mobile := main.get_node_or_null("MobileControls")
    if not _expect(streamer != null and player != null and mobile != null, "main scene missing streamer/player/mobile controls"):
        return
    if not _expect(not bool(streamer.call("is_ixelles_active")), "Ixelles should not be loaded at Midi spawn"):
        return

    mobile.call("ensure_gameplay_controls_for_test")
    if not _expect(_ixelles_button_present(mobile), "mobile CARTE does not expose IXELLES / ELSENE"):
        return

    # Freeze automatic player-follow updates while this test drives the observer explicitly.
    streamer.set_process(false)
    var center: Vector3 = streamer.call("get_ixelles_world_center")
    if not _expect(center.distance_to(Vector3(713.20577208066, 0.0, 916.46414926197)) < 0.1, "Ixelles center drifted from committed EPSG:31370 mapping: %s" % [center]):
        return

    streamer.call("force_observer_for_test", center + Vector3(600.0, 0.0, 0.0), Vector3(-100.0, 0.0, 0.0))
    if not await _wait_until(_cell_ready.bind(streamer), 90):
        _fail("predictive approach failed to load real Ixelles cell")
        return
    if not _expect(not _collision_present(streamer), "visual prefetch at 600 m unexpectedly enabled heavy collision"):
        return

    streamer.call("force_observer_for_test", center, Vector3.ZERO)
    if not await _wait_until(_collision_present.bind(streamer), 30):
        _fail("near-player collision tier failed to activate")
        return
    var backend: Node = streamer.call("get_backend")
    var instance: Node = backend.call("get_instance", CELL_ID)
    if not _expect(int(instance.get("dynamic_collision_build_ms")) >= 0, "collision build telemetry unavailable"):
        return

    streamer.call("force_observer_for_test", center + Vector3(400.0, 0.0, 0.0), Vector3.ZERO)
    await _wait_frames(4)
    if not _expect(bool(streamer.call("is_ixelles_active")), "visual cell should remain active inside unload hysteresis"):
        return
    if not _expect(not _collision_present(streamer), "collision tier should release outside 260 m"):
        return

    streamer.call("force_observer_for_test", center + Vector3(1000.0, 0.0, 0.0), Vector3.ZERO)
    await _wait_frames(4)
    if not _expect(not bool(streamer.call("is_ixelles_active")), "Ixelles visual cell should unload beyond 850 m"):
        return

    var travel_started := bool(streamer.call("request_ixelles_fast_travel", player))
    if not _expect(travel_started, "streamed Ixelles fast travel request was rejected"):
        return
    var fast_travel_done := await _wait_until(_fast_travel_done.bind(streamer, player, center), 180)
    if not fast_travel_done:
        _fail("streamed Ixelles fast travel did not place the player in the loaded cell")
        return
    if not _expect(player.global_position.y > -0.5, "Ixelles fast travel placed player below terrain"):
        return

    var metrics: Dictionary = streamer.call("get_metrics")
    var scheduler: Dictionary = metrics.get("scheduler", {})
    var backend_metrics: Dictionary = metrics.get("backend", {})
    if not _expect(int(scheduler.get("duplicate_activation_attempts", -1)) == 0, "duplicate world-stream activation detected"):
        return
    if not _expect(int(backend_metrics.get("failed_load_count", -1)) == 0 and int(backend_metrics.get("collision_apply_count", 0)) >= 2, "backend collision/load metrics invalid: %s" % [backend_metrics]):
        return

    print("BRUSSELS_WORLD_STREAMING_RUNTIME_OK: main scene streams Ixelles, toggles collision tier, exposes mobile travel and lands player on source-backed Place Stephanie witness; center=%s player=%s metrics=%s" % [center, player.global_position, metrics])
    main.queue_free()
    quit(0)
