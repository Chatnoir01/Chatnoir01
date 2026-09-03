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

    var missing_path := CSGPolygon3D.new()
    missing_path.name = "Road_%d_PathModeMissingPath" % ROAD_ID
    missing_path.mode = CSGPolygon3D.MODE_PATH
    missing_path.path_node = NodePath("")
    world.add_child(missing_path)
    await process_frame

    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("MODE_PATH CSGPolygon3D without a Path3D was accepted as rendered road geometry")
        return

    print("AUTOMATIC_ROAD_CSG_PATH_MODE_GREEN: road_id=%d missing_path_rejected=true destination_advertisable=false jouable=false" % ROAD_ID)
    quit(0)
