extends SceneTree

const RUNTIME_SCRIPT := preload("res://scripts/grand_place_official_lod2_contour_runtime.gd")

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error(message)

func _run() -> void:
    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "GrandPlaceContourRollbackProbe"
    root.add_child(runtime)
    runtime.set("_owner_bounds", {"probe-owner": Rect2(Vector2(-5.0, -5.0), Vector2(10.0, 10.0))})

    var csg := CSGBox3D.new()
    csg.name = "LegacyOsmCsg"
    csg.position = Vector3.ZERO
    csg.visible = true
    csg.use_collision = true
    root.add_child(csg)

    runtime.call("_mask_osm_node_if_replaced", csg)
    _check(not csg.visible, "precondition: overlapping OSM CSG must be masked")
    _check(not csg.use_collision, "precondition: overlapping OSM CSG collision must be disabled")
    _check(csg.has_meta("replaced_by_urbis_building"), "precondition: replacement ownership marker must exist")

    runtime.call("_reset_partial_build_state")
    _check(csg.visible, "rollback: OSM visibility must be restored before official contour geometry is removed")
    _check(csg.use_collision, "rollback: OSM collision must be restored before official contour geometry is removed")
    _check(not csg.has_meta("replaced_by_urbis_building"), "rollback: contour replacement marker must be removed")

    var body := StaticBody3D.new()
    body.name = "LegacyOsmCollision"
    body.position = Vector3.ZERO
    body.visible = true
    body.collision_layer = 7
    body.collision_mask = 11
    body.set_meta("replaced_by_urbis_building", "previous-owner")
    root.add_child(body)

    runtime.set("_owner_bounds", {"probe-owner": Rect2(Vector2(-5.0, -5.0), Vector2(10.0, 10.0))})
    runtime.call("_mask_osm_node_if_replaced", body)
    _check(body.collision_layer == 0 and body.collision_mask == 0, "precondition: overlapping OSM collision object must be disabled")
    runtime.call("_reset_partial_build_state")
    _check(body.visible, "rollback: original collision-node visibility must be restored")
    _check(body.collision_layer == 7 and body.collision_mask == 11, "rollback: exact collision layer/mask must be restored")
    _check(str(body.get_meta("replaced_by_urbis_building", "")) == "previous-owner", "rollback: pre-existing ownership metadata must be restored exactly")

    runtime.queue_free()
    csg.queue_free()
    body.queue_free()

    if failures.is_empty():
        print("GRAND_PLACE_CONTOUR_OSM_MASK_ROLLBACK_OK")
        quit(0)
    else:
        print("GRAND_PLACE_CONTOUR_OSM_MASK_ROLLBACK_RED: failures=%d" % failures.size())
        quit(1)
