extends SceneTree

const SCRIPT := preload("res://game/scripts/grand_place_granite_paving.gd")

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_PAVING_COLLISION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var root := Node3D.new()
    root.name = "GrandPlacePavingCollisionTestRoot"
    get_root().add_child(root)
    var paving := Node3D.new()
    paving.set_script(SCRIPT)
    root.add_child(paving)
    await process_frame
    await physics_frame
    if not bool(paving.call("geometry_loaded")):
        _fail("official paving did not load")
        return
    if not bool(paving.call("collision_ready")):
        _fail("official paving collision missing")
        return
    var body := paving.get_node_or_null("OfficialGraniteStreetSurfaceCollision") as StaticBody3D
    if body == null:
        _fail("named static body missing")
        return
    var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collision == null or collision.shape == null:
        _fail("collision shape missing")
        return
    if str(body.get_meta("geometry_source", "")) != "same_official_granite_mesh":
        _fail("collision provenance drifted")
        return
    print("GRAND_PLACE_PAVING_COLLISION_OK: area=%.2f source=%s" % [float(paving.call("source_polygon_area_m2")), str(paving.call("source_feature_id"))])
    quit(0)
