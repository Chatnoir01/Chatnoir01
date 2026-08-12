extends SceneTree

const BOURSE_ROUTE_ANCHOR := Vector2(81.54, -664.58)
const BOURSE_URBIS_CENTER := Vector2(172.5915, -672.2825)
const DETAIL_RADIUS_M := 180.0


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BOURSE_CONTEXT_DETAIL_FAIL: %s" % message)
    quit(1)


func _near(position: Vector3, anchor: Vector2) -> bool:
    return Vector2(position.x, position.z).distance_to(anchor) <= DETAIL_RADIUS_M


func _verify_multimesh_primitive() -> void:
    var probe := MultiMesh.new()
    probe.transform_format = MultiMesh.TRANSFORM_3D
    probe.mesh = BoxMesh.new()
    probe.instance_count = 1
    var expected := Transform3D(Basis.IDENTITY, Vector3(123.0, 4.0, -456.0))
    probe.set_instance_transform(0, expected)
    var actual := probe.get_instance_transform(0)
    if actual.origin.distance_to(expected.origin) > 0.001:
        _fail("bare MultiMesh failed transform retention: expected %s got %s" % [expected.origin, actual.origin])


func _run() -> void:
    _verify_multimesh_primitive()

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
            if absf(box.size.y - 0.12) < 0.001 and _near(box.position, BOURSE_ROUTE_ANCHOR):
                bourse_sidewalks += 1
    if bourse_sidewalks < 2:
        _fail("expected source-aligned Bourse road context to generate sidewalks; got %d" % bourse_sidewalks)
        return

    var windows_node := scene.get_node_or_null("BrusselsOSM/GeneratedFacadeDetails/CorridorFacadeWindows") as MultiMeshInstance3D
    if windows_node == null or windows_node.multimesh == null:
        _fail("corridor facade-window MultiMesh is missing")
        return

    var bourse_route_windows := 0
    var bourse_urbis_windows := 0
    var min_route_distance := INF
    var min_urbis_distance := INF
    var min_x := INF
    var max_x := -INF
    var min_z := INF
    var max_z := -INF

    for index in range(windows_node.multimesh.instance_count):
        var transform := windows_node.multimesh.get_instance_transform(index)
        var point := Vector2(transform.origin.x, transform.origin.z)
        min_x = minf(min_x, point.x)
        max_x = maxf(max_x, point.x)
        min_z = minf(min_z, point.y)
        max_z = maxf(max_z, point.y)
        var route_distance := point.distance_to(BOURSE_ROUTE_ANCHOR)
        var urbis_distance := point.distance_to(BOURSE_URBIS_CENTER)
        min_route_distance = minf(min_route_distance, route_distance)
        min_urbis_distance = minf(min_urbis_distance, urbis_distance)
        if route_distance <= DETAIL_RADIUS_M:
            bourse_route_windows += 1
        if urbis_distance <= DETAIL_RADIUS_M:
            bourse_urbis_windows += 1

    print(
        "BOURSE_CONTEXT_DIAGNOSTIC: windows=%d bounds=[%.2f,%.2f]-[%.2f,%.2f] min_route=%.2f min_urbis=%.2f route_hits=%d urbis_hits=%d" %
        [windows_node.multimesh.instance_count, min_x, min_z, max_x, max_z, min_route_distance, min_urbis_distance, bourse_route_windows, bourse_urbis_windows]
    )

    if bourse_urbis_windows < 1:
        _fail("scene facade MultiMesh has no positioned windows around authoritative Bourse context")
        return

    print(
        "BOURSE_CONTEXT_DETAIL_OK: %d sidewalks, %d facade windows inside %.0f m of UrbIS Bourse center; quantitative frontage-density blocker remains open" %
        [bourse_sidewalks, bourse_urbis_windows, DETAIL_RADIUS_M]
    )
    scene.queue_free()
    quit(0)
