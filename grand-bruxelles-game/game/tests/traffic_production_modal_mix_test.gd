extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_PRODUCTION_MODAL_MIX_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var scene_resource := load("res://game/main.tscn") as PackedScene
    if scene_resource == null:
        _fail("main scene did not load")
        return
    var main := scene_resource.instantiate()
    get_root().add_child(main)
    for _frame in range(8):
        await process_frame

    var manager := main.get_node_or_null("TrafficManager") as TrafficManagerNpcCrossingExtension
    if manager == null:
        _fail("TrafficManager missing from production scene")
        return
    if manager.scooter_share != 0.0 or manager.motorcycle_share != 0.0:
        _fail("production scene invents powered two-wheeler shares without source-backed evidence")
        return

    var counts: Dictionary = manager.get_active_archetype_counts()
    if int(counts.get("scooter", 0)) != 0 or int(counts.get("motorcycle", 0)) != 0:
        _fail("production runtime spawned powered two-wheelers from an unsourced modal mix")
        return

    print("TRAFFIC_PRODUCTION_MODAL_MIX_OK: unsourced scooter/motorcycle shares disabled in production")
    main.queue_free()
    quit(0)
