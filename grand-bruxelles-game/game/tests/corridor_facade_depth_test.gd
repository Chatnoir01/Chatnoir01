extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CORRIDOR_FACADE_DEPTH_FAIL: %s" % message)
    quit(1)

func _instance_count(node: Node) -> int:
    if node == null or not node is MultiMeshInstance3D:
        return 0
    var mm := (node as MultiMeshInstance3D).multimesh
    return mm.instance_count if mm != null else 0

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await process_frame

    var details := scene.get_node_or_null("BrusselsOSM/GeneratedFacadeDetails")
    if details == null:
        _fail("GeneratedFacadeDetails is missing")
        return

    var windows := _instance_count(details.get_node_or_null("CorridorFacadeWindows"))
    var lintels := _instance_count(details.get_node_or_null("CorridorFacadeLintels"))
    var sills := _instance_count(details.get_node_or_null("CorridorFacadeSills"))
    var jambs := _instance_count(details.get_node_or_null("CorridorFacadeJambs"))
    var canopies := _instance_count(details.get_node_or_null("CorridorShopCanopies"))

    if windows < 1:
        _fail("baseline corridor windows disappeared")
        return
    if lintels != windows:
        _fail("every visible corridor window must receive exactly one lintel; windows=%d lintels=%d" % [windows, lintels])
        return
    if sills != windows:
        _fail("every visible corridor window must receive exactly one sill; windows=%d sills=%d" % [windows, sills])
        return
    if jambs != windows * 2:
        _fail("every visible corridor window must receive exactly two jambs; windows=%d jambs=%d" % [windows, jambs])
        return
    if canopies < 1:
        _fail("no shopfront canopy articulation was generated")
        return

    print("CORRIDOR_FACADE_DEPTH_OK windows=%d lintels=%d sills=%d jambs=%d canopies=%d" % [windows, lintels, sills, jambs, canopies])
    scene.queue_free()
    quit(0)
