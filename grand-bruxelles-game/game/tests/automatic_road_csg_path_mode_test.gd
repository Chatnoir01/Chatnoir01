extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 359177328


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_CSG_PATH_MODE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)

    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)

    # Path mode has a valid default polygon, but cannot render without Path3D.
    var missing_path := CSGPolygon3D.new()
    missing_path.name = "Road_%d_PathModeMissingPath" % ROAD_ID
    missing_path.mode = CSGPolygon3D.MODE_PATH
    missing_path.path_node = NodePath("")
    world.add_child(missing_path)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("MODE_PATH CSGPolygon3D without a Path3D was accepted as rendered road geometry")
        return
    missing_path.queue_free()
    await process_frame

    # A referenced Path3D with no usable curve still produces no extrusion.
    var empty_path := Path3D.new()
    empty_path.name = "EmptyRoadPath"
    empty_path.curve = Curve3D.new()
    world.add_child(empty_path)
    var empty_curve_polygon := CSGPolygon3D.new()
    empty_curve_polygon.name = "Road_%d_PathModeEmptyCurve" % ROAD_ID
    empty_curve_polygon.mode = CSGPolygon3D.MODE_PATH
    empty_curve_polygon.path_node = NodePath("../EmptyRoadPath")
    world.add_child(empty_curve_polygon)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("MODE_PATH CSGPolygon3D with an empty Path3D curve was accepted as rendered road geometry")
        return
    empty_curve_polygon.queue_free()
    empty_path.queue_free()
    await process_frame

    # Preserve a legitimate path extrusion as positive renderable proof.
    var usable_path := Path3D.new()
    usable_path.name = "UsableRoadPath"
    var usable_curve := Curve3D.new()
    usable_curve.add_point(Vector3(0.0, 0.0, 0.0))
    usable_curve.add_point(Vector3(0.0, 0.0, -8.0))
    usable_path.curve = usable_curve
    world.add_child(usable_path)
    var usable_path_polygon := CSGPolygon3D.new()
    usable_path_polygon.name = "Road_%d_PathModeUsableCurve" % ROAD_ID
    usable_path_polygon.mode = CSGPolygon3D.MODE_PATH
    usable_path_polygon.path_node = NodePath("../UsableRoadPath")
    world.add_child(usable_path_polygon)
    await process_frame
    if not resolver._road_is_rendered(world, ROAD_ID):
        _fail("MODE_PATH CSGPolygon3D with a usable Path3D curve was incorrectly rejected")
        return

    print("AUTOMATIC_ROAD_CSG_PATH_MODE_GREEN: road_id=%d missing_path_rejected=true empty_curve_rejected=true usable_curve_accepted=true destination_advertisable=false jouable=false" % ROAD_ID)
    quit(0)
