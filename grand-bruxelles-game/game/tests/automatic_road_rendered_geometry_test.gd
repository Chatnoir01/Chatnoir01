extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 359177328


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_RENDERED_GEOMETRY_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)

    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)

    # A name-only decoy must never authorize a player-visible destination.
    var name_only_decoy := Node3D.new()
    name_only_decoy.name = "Road_%d_NameOnlyDecoy" % ROAD_ID
    world.add_child(name_only_decoy)
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("name-only Node3D was accepted as rendered road geometry")
        return
    name_only_decoy.queue_free()
    await process_frame

    # Even real geometry is not player-visible evidence while hidden.
    var road_geometry := CSGBox3D.new()
    road_geometry.name = "Road_%d_VisibleGeometry" % ROAD_ID
    road_geometry.size = Vector3(4.0, 0.2, 12.0)
    road_geometry.visible = false
    world.add_child(road_geometry)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("hidden GeometryInstance3D was accepted as rendered road geometry")
        return

    road_geometry.visible = true
    await process_frame
    if not resolver._road_is_rendered(world, ROAD_ID):
        _fail("visible GeometryInstance3D with exact road identity was rejected")
        return

    print("AUTOMATIC_ROAD_RENDERED_GEOMETRY_GREEN: road_id=%d name_only_rejected=true hidden_geometry_rejected=true visible_geometry_accepted=true destination_advertisable=false jouable=false" % ROAD_ID)
    quit(0)
