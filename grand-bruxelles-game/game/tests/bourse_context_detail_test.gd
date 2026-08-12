extends SceneTree

const BOURSE_ANCHOR := Vector2(81.54, -664.58)
const DETAIL_RADIUS_M := 180.0


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BOURSE_CONTEXT_DETAIL_FAIL: %s" % message)
    quit(1)


func _near_bourse(position: Vector3) -> bool:
    return Vector2(position.x, position.z).distance_to(BOURSE_ANCHOR) <= DETAIL_RADIUS_M


func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame

    var roads := scene.get_node_or_null("BrusselsOSM/GeneratedRoads") as Node3D
    if roads == null:
        _fail("generated road root is missing")
        return

    var bourse_sidewalks := 0
    for child in roads.get_children():
        if child is CSGBox3D:
            var box := child as CSGBox3D
            if absf(box.size.y - 0.12) < 0.001 and _near_bourse(box.position):
                bourse_sidewalks += 1
    if bourse_sidewalks < 2:
        _fail("expected source-aligned Bourse road context to generate sidewalks; got %d" % bourse_sidewalks)
        return

    var windows_node := scene.get_node_or_null("BrusselsOSM/GeneratedFacadeDetails/CorridorFacadeWindows") as MultiMeshInstance3D
    var bourse_windows := 0
    if windows_node != null and windows_node.multimesh != null:
        for index in range(windows_node.multimesh.instance_count):
            var transform := windows_node.multimesh.get_instance_transform(index)
            if _near_bourse(transform.origin):
                bourse_windows += 1

    print(
        "BOURSE_CONTEXT_DETAIL_OK: %d sidewalks, %d existing facade windows inside %.0f m; frontage-density blocker remains open" %
        [bourse_sidewalks, bourse_windows, DETAIL_RADIUS_M]
    )
    scene.queue_free()
    quit(0)
