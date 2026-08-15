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

func _color_key(color: Color) -> String:
    return "%.3f,%.3f,%.3f" % [color.r, color.g, color.b]

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
    var canopy_node := details.get_node_or_null("CorridorShopCanopies") as MultiMeshInstance3D
    var canopies := _instance_count(canopy_node)

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
    if canopies < 1 or canopy_node == null or canopy_node.multimesh == null:
        _fail("no shopfront canopy articulation was generated")
        return
    if not canopy_node.multimesh.use_colors:
        _fail("shop canopies must use per-instance color variation")
        return

    var distinct := {}
    for index: int in range(canopy_node.multimesh.instance_count):
        var color := canopy_node.multimesh.get_instance_color(index)
        distinct[_color_key(color)] = true
        var max_channel := maxf(color.r, maxf(color.g, color.b))
        var min_channel := minf(color.r, minf(color.g, color.b))
        if max_channel > 0.30 or min_channel < 0.05:
            _fail("canopy palette escaped restrained street-level bounds at %d: %s" % [index, _color_key(color)])
            return
    if distinct.size() < 4:
        _fail("shop canopies remain too synchronized; distinct colors=%d" % distinct.size())
        return

    print("CORRIDOR_FACADE_DEPTH_OK windows=%d lintels=%d sills=%d jambs=%d canopies=%d canopy_colors=%d" % [windows, lintels, sills, jambs, canopies, distinct.size()])
    scene.queue_free()
    quit(0)
