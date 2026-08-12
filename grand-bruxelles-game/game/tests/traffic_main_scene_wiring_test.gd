extends SceneTree

const CONTRACT := preload("res://game/scripts/traffic_runtime_contract.gd")
const MAIN_SCENE := preload("res://game/main.tscn")
const EXPECTED_SCRIPT_PATH := "res://game/scripts/traffic_manager_tow_extension.gd"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_MAIN_SCENE_WIRING_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main_instance: Node = MAIN_SCENE.instantiate()
    if main_instance == null:
        _fail("main scene could not instantiate")
        return

    var manager: Node = main_instance.get_node_or_null("TrafficManager")
    if manager == null:
        _fail("Main/TrafficManager node is missing")
        return

    var manager_script: Script = manager.get_script() as Script
    if manager_script == null or manager_script.resource_path != EXPECTED_SCRIPT_PATH:
        _fail("TrafficManager is not wired to the canonical tow extension")
        return

    # Scene wiring validation should load the real road/control fallback without
    # creating dozens of runtime actors inside the full visual scene.
    manager.set("auto_spawn_runtime", false)
    root.add_child(main_instance)
    await process_frame
    await process_frame

    var missing: PackedStringArray = CONTRACT.validate_manager(manager, true)
    if not missing.is_empty():
        _fail("canonical manager contract missing methods: %s" % ", ".join(missing))
        return

    for root_name: String in CONTRACT.REQUIRED_MANAGER_ROOTS:
        if manager.get_node_or_null(root_name) == null:
            _fail("required runtime root missing after ready: %s" % root_name)
            return
    if manager.get_node_or_null("TowServices") == null:
        _fail("TowServices runtime root missing after ready")
        return

    var route_count := int(manager.call("get_route_count"))
    var graph_nodes := int(manager.call("get_graph_node_count"))
    var graph_edges := int(manager.call("get_graph_edge_count"))
    if route_count <= 0 or graph_nodes <= 0 or graph_edges <= 0:
        _fail("main scene traffic data did not build a usable road graph")
        return

    if int(manager.call("get_tow_service_count")) != 0:
        _fail("tow services should start empty before any wreck")
        return

    print(
        "TRAFFIC_MAIN_SCENE_WIRING_OK: canonical tow manager, %d roads, %d nodes, %d directed edges" %
        [route_count, graph_nodes, graph_edges]
    )
    main_instance.queue_free()
    await process_frame
    quit(0)
