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
    var shopfronts := _instance_count(details.get_node_or_null("CorridorShopfronts"))
    var lintels := _instance_count(details.get_node_or_null("CorridorFacadeLintels"))
    var sills := _instance_count(details.get_node_or_null("CorridorFacadeSills"))
    var jambs := _instance_count(details.get_node_or_null("CorridorFacadeJambs"))

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
    if shopfronts < 1:
        _fail("baseline corridor shopfronts disappeared")
        return

    var canopy_total := 0
    var canopy_groups := 0
    var distinct := {}
    for child: Node in details.get_children():
        if not child.name.begins_with("CorridorShopCanopies") or not child is MultiMeshInstance3D:
            continue
        var canopy_node := child as MultiMeshInstance3D
        var mm := canopy_node.multimesh
        if mm == null or mm.instance_count < 1:
            continue
        var box_mesh := mm.mesh as BoxMesh
        if box_mesh == null:
            _fail("canopy group does not use expected low-cost BoxMesh")
            return
        var material := box_mesh.material as StandardMaterial3D
        if material == null:
            _fail("canopy group has no StandardMaterial3D")
            return
        var color := material.albedo_color
        var max_channel := maxf(color.r, maxf(color.g, color.b))
        var min_channel := minf(color.r, minf(color.g, color.b))
        if max_channel > 0.30 or min_channel < 0.05:
            _fail("canopy palette escaped restrained street-level bounds: %s" % _color_key(color))
            return
        distinct[_color_key(color)] = true
        canopy_total += mm.instance_count
        canopy_groups += 1

    if canopy_total != shopfronts:
        _fail("each existing shopfront must keep exactly one canopy; shops=%d canopies=%d" % [shopfronts, canopy_total])
        return
    if canopy_groups < 4 or distinct.size() < 4:
        _fail("shop canopies remain too synchronized; groups=%d distinct_colors=%d" % [canopy_groups, distinct.size()])
        return

    print("CORRIDOR_FACADE_DEPTH_OK windows=%d lintels=%d sills=%d jambs=%d shopfronts=%d canopies=%d canopy_groups=%d canopy_colors=%d" % [windows, lintels, sills, jambs, shopfronts, canopy_total, canopy_groups, distinct.size()])
    scene.queue_free()
    quit(0)
